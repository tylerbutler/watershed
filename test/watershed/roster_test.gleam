//// Tests for the connected-membership roster the consensus kernels draw their
//// quorum from.
////
//// The roster is not observable through any facade, so these drive
//// `runtime_core` directly and read `Core.members`. The property that matters
//// is that every replica derives the *same* membership at the same sequence
//// point: seeded from the handshake, widened by a sequenced `"join"`, narrowed
//// by a sequenced `"leave"`, and replaced wholesale on reconnect.
////
//// Both system messages are built here in the shape the server actually sends
//// — `clientId` null, `contents` null, payload as JSON text in `data` — which
//// differs per message type: a bare string for `"leave"`, an object carrying
//// `clientId` for `"join"`. Fixtures that fabricate a friendlier shape are how
//// the previous version of this path passed its tests while being dead in
//// production.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import startest/expect

import signet/types as token
import spillway/message
import spillway/types

import watershed/channel
import watershed/client_id
import watershed/pact_map_kernel
import watershed/runtime_core.{type Core}
import watershed/wire/ops

const our_client_id = "default_doc_2"

const peer_client_id = "default_doc_1"

const third_client_id = "default_doc_3"

const reconnect_client_id = "default_doc_9"

// ─────────────────────────────────────────────────────────────────────────────
// Seeding
// ─────────────────────────────────────────────────────────────────────────────

pub fn roster_seeds_from_initial_clients_test() {
  let core = bootstrap_with([peer_client_id, third_client_id])

  members(core)
  |> expect.to_equal(ids([our_client_id, peer_client_id, third_client_id]))
}

/// The server builds `initialClients` from the document's presence map, which
/// need not yet contain the client it is answering — so self is unioned in
/// rather than assumed present.
pub fn roster_includes_self_when_absent_from_initial_clients_test() {
  let core = bootstrap_with([])

  members(core) |> expect.to_equal(ids([our_client_id]))
}

// ─────────────────────────────────────────────────────────────────────────────
// Join / leave
// ─────────────────────────────────────────────────────────────────────────────

pub fn join_widens_the_roster_test() {
  let core = bootstrap_with([peer_client_id])

  let core = apply(core, join_msg(third_client_id, 1))

  members(core)
  |> expect.to_equal(ids([our_client_id, peer_client_id, third_client_id]))
}

pub fn leave_narrows_the_roster_test() {
  let core = bootstrap_with([peer_client_id, third_client_id])

  let core = apply(core, leave_msg(third_client_id, 1))

  members(core) |> expect.to_equal(ids([our_client_id, peer_client_id]))
}

/// A re-joining client id is already in the set; membership is a set, not a
/// count, so the second join is not a second member.
pub fn repeated_join_is_idempotent_test() {
  let core = bootstrap_with([peer_client_id])

  let core = apply(core, join_msg(peer_client_id, 1))

  members(core) |> expect.to_equal(ids([our_client_id, peer_client_id]))
}

/// A leave for a client that never joined leaves the roster untouched, the
/// same way it is a no-op for every kernel.
pub fn leave_for_unknown_client_is_noop_test() {
  let core = bootstrap_with([peer_client_id])

  let core = apply(core, leave_msg("default_doc_77", 1))

  members(core) |> expect.to_equal(ids([our_client_id, peer_client_id]))
}

/// A malformed payload is ignored rather than failing the batch — but it must
/// not be *silently* the same as a well-formed one, which is what reading the
/// wrong field amounted to before.
pub fn membership_message_without_data_is_ignored_test() {
  let core = bootstrap_with([peer_client_id])
  let before = members(core)

  let core = apply(core, system_msg("join", None, 1))
  let core = apply(core, system_msg("leave", None, 2))

  members(core) |> expect.to_equal(before)
}

/// A `"join"` payload is an object, a `"leave"` payload a bare string. Feeding
/// each the other's shape must not move the roster — if it did, the two
/// decoders would be interchangeable and the distinction meaningless.
pub fn membership_payload_shapes_are_not_interchangeable_test() {
  let core = bootstrap_with([peer_client_id])
  let before = members(core)

  let bare = json.to_string(json.string(third_client_id))
  let object =
    json.to_string(json.object([#("clientId", json.string(peer_client_id))]))

  let core = apply(core, system_msg("join", Some(bare), 1))
  let core = apply(core, system_msg("leave", Some(object), 2))

  members(core) |> expect.to_equal(before)
}

// ─────────────────────────────────────────────────────────────────────────────
// Checkpoint roster
// ─────────────────────────────────────────────────────────────────────────────

/// The checkpoint roster governs *replay*, and the handshake's roster takes
/// over at the hand-off to live. Pinning the hand-off matters because the
/// checkpoint roster is stale by definition — everything that happened since
/// is in the log, and once the log is exhausted the handshake is authoritative.
pub fn go_live_adopts_the_handshake_roster_over_the_checkpoint_test() {
  let core =
    bootstrap_from_summary(
      members: [peer_client_id, third_client_id],
      channels: [],
      at: 5,
      initial_clients: [peer_client_id],
      initial_messages: [],
    )

  members(core) |> expect.to_equal(ids([our_client_id, peer_client_id]))
}

/// The checkpoint roster is a starting point, not a fixed set: the sequenced
/// membership messages replayed after it still move it, and a proposal
/// sequenced later is judged against the moved roster.
pub fn checkpoint_roster_is_advanced_by_replayed_membership_test() {
  let core =
    bootstrap_from_summary(
      members: [our_client_id, peer_client_id, third_client_id],
      channels: [#("pact", channel.PactMapSnapshot([]))],
      at: 5,
      initial_clients: [],
      initial_messages: [
        leave_msg(third_client_id, 6),
        pact_set_msg(
          author: peer_client_id,
          sn: 7,
          key: "bpm",
          value: json.int(128),
        ),
      ],
    )

  // The departed client is not owed a signoff the pact would wait on forever.
  let assert Some(pending) = runtime_core.pact_map_pending(core, "pact", "bpm")
  pending.expected_signoffs
  |> list.sort(by: int.compare)
  |> expect.to_equal(ids([our_client_id, peer_client_id]))
}

/// The assertion the consensus replay work could not make until the blob
/// carried a roster.
///
/// A proposal sequenced *after* the checkpoint freezes its signoff list from
/// the roster at that moment. A client that was present froze it from the
/// three clients in the room. A client bootstrapping from the checkpoint must
/// reconstruct the same list — with a rosterless checkpoint it saw an empty
/// room, froze a signoff list of one, and treated a pact the room was still
/// deciding as already settled.
pub fn a_proposal_after_the_checkpoint_reconstructs_the_present_signoff_list_test() {
  let core =
    bootstrap_from_summary(
      members: [our_client_id, peer_client_id, third_client_id],
      channels: [#("pact", channel.PactMapSnapshot([]))],
      at: 5,
      initial_clients: [],
      initial_messages: [
        pact_set_msg(
          author: peer_client_id,
          sn: 6,
          key: "bpm",
          value: json.int(128),
        ),
      ],
    )

  let assert Some(pending) = runtime_core.pact_map_pending(core, "pact", "bpm")
  pending.expected_signoffs
  |> list.sort(by: int.compare)
  |> expect.to_equal(ids([our_client_id, peer_client_id, third_client_id]))
}

// ─────────────────────────────────────────────────────────────────────────────
// Reconnect
// ─────────────────────────────────────────────────────────────────────────────

/// On reconnect the fresh handshake is authoritative: the roster is replaced,
/// not merged. Merging would resurrect a client that left during the gap, and
/// its signoffs would never drain.
pub fn reconnect_replaces_the_roster_test() {
  let core = bootstrap_with([peer_client_id, third_client_id])

  let core =
    runtime_core.adopt_reconnect(
      core,
      message.ConnectedMessage(
        ..connected_message([peer_client_id]),
        client_id: reconnect_client_id,
      ),
    )

  members(core)
  |> expect.to_equal(ids([reconnect_client_id, peer_client_id]))
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures
// ─────────────────────────────────────────────────────────────────────────────

fn members(core: Core) -> List(Int) {
  core.members |> set.to_list |> list.sort(by: int.compare)
}

fn ids(client_ids: List(String)) -> List(Int) {
  client_ids
  |> list.map(client_id.to_int)
  |> set.from_list
  |> set.to_list
  |> list.sort(by: int.compare)
}

fn null_dynamic() -> Dynamic {
  case json.parse(json.to_string(json.null()), decode.dynamic) {
    Ok(value) -> value
    Error(_) -> panic as "expected null to decode as dynamic"
  }
}

fn apply(core: Core, msg: types.SequencedDocumentMessage) -> Core {
  case runtime_core.handle_sequenced(core, msg) {
    Ok(#(core, _)) -> core
    Error(_) -> panic as "expected handle_sequenced to succeed"
  }
}

fn bootstrap_with(initial_clients: List(String)) -> Core {
  case
    runtime_core.bootstrap(connected_message(initial_clients), summary: None)
  {
    Ok(runtime_core.Complete(core)) -> core
    Ok(runtime_core.MissingPrefix(..)) ->
      panic as "expected bootstrap to complete without catch-up"
    Error(_) -> panic as "expected bootstrap to succeed"
  }
}

/// Bootstrap seeded from a summary checkpoint, then replaying
/// `initial_messages` on top of it.
fn bootstrap_from_summary(
  members members: List(String),
  channels channels: List(#(String, channel.Snapshot)),
  at at: Int,
  initial_clients initial_clients: List(String),
  initial_messages initial_messages: List(types.SequencedDocumentMessage),
) -> Core {
  let connected =
    message.ConnectedMessage(
      ..connected_message(initial_clients),
      initial_messages: initial_messages,
      checkpoint_sequence_number: Some(at),
    )
  let summary =
    runtime_core.Summary(
      sequence_number: at,
      channels: channels,
      members: list.map(members, client_id.to_int),
    )

  case runtime_core.bootstrap(connected, summary: Some(summary)) {
    Ok(runtime_core.Complete(core)) -> core
    Ok(runtime_core.MissingPrefix(..)) ->
      panic as "expected bootstrap to complete without catch-up"
    Error(_) -> panic as "expected bootstrap to succeed"
  }
}

/// A sequenced `PactMap` proposal, as a peer's `Set` arrives on the wire.
fn pact_set_msg(
  author author: String,
  sn sn: Int,
  key key: String,
  value value: json.Json,
) -> types.SequencedDocumentMessage {
  let contents =
    ops.encode_pact_map_envelope(
      "pact",
      pact_map_kernel.Set(key, Some(value), 0),
    )
  types.SequencedDocumentMessage(
    ..system_msg("op", None, sn),
    client_id: Some(author),
    client_sequence_number: 1,
    contents: to_dynamic(contents),
  )
}

fn to_dynamic(value: json.Json) -> Dynamic {
  case json.parse(json.to_string(value), decode.dynamic) {
    Ok(parsed) -> parsed
    Error(_) -> panic as "fixture JSON failed to re-parse"
  }
}

/// A sequenced `"join"`: payload is an object carrying the arriving client's
/// id, encoded as JSON text in `data`.
fn join_msg(joining: String, sn: Int) -> types.SequencedDocumentMessage {
  system_msg(
    "join",
    Some(
      json.to_string(
        json.object([
          #("clientId", json.string(joining)),
          #("detail", json.object([])),
        ]),
      ),
    ),
    sn,
  )
}

/// A sequenced `"leave"`: payload is the departing client's id as a bare JSON
/// string, encoded as JSON text in `data`.
fn leave_msg(leaving: String, sn: Int) -> types.SequencedDocumentMessage {
  system_msg("leave", Some(json.to_string(json.string(leaving))), sn)
}

fn system_msg(
  message_type: String,
  data: option.Option(String),
  sn: Int,
) -> types.SequencedDocumentMessage {
  types.SequencedDocumentMessage(
    client_id: None,
    sequence_number: sn,
    minimum_sequence_number: 0,
    client_sequence_number: -1,
    reference_sequence_number: sn - 1,
    message_type: message_type,
    contents: null_dynamic(),
    metadata: None,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 0,
    data: data,
  )
}

fn connected_message(
  initial_clients: List(String),
) -> message.ConnectedMessage {
  message.ConnectedMessage(
    claims: token.TokenClaims(
      document_id: "doc",
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
    initial_clients: list.map(initial_clients, signal_client),
    initial_messages: [],
    initial_signals: [],
    supported_versions: ["^0.1.0"],
    supported_features: dict.new(),
    version: "^0.1.0",
    timestamp: None,
    checkpoint_sequence_number: Some(0),
    epoch: None,
    relay_service_agent: None,
    summary_context: None,
  )
}

fn signal_client(client_id: String) -> types.SignalClient {
  types.SignalClient(
    client_id: client_id,
    client: types.Client(
      mode: types.WriteMode,
      details: types.ClientDetails(
        capabilities: types.ClientCapabilities(interactive: True),
        client_type: None,
        environment: None,
        device: None,
      ),
      permission: [],
      user: token.User(id: client_id, properties: dict.new()),
      scopes: [],
      timestamp: None,
    ),
    client_connection_number: None,
    reference_sequence_number: None,
  )
}
