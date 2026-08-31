//// SharedDirectory ↔ runtime integration tests: the directory kernel driven
//// through `runtime_core` + `channel` + the wire codecs, single-client and in
//// a two-client sequencer simulation. Kernel-internal semantics are covered by
//// `directory_kernel_test`/`directory_fuzz_test`; these pin the *wiring*:
//// operation encode/decode, attach/snapshot round-trip, SequencedMeta
//// threading (author, refSeq, the kernel message-id carried in the operation),
//// and convergence.

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
import watershed/directory_kernel
import watershed/handle
import watershed/runtime_core.{type Core}
import watershed/wire

const id_a = "default_doc_1"

const id_b = "default_doc_2"

const directory_address = "dir-1"

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

/// Two cores driven by a shared, in-order sequencer. `sequence_number` is
/// the last server sequence number stamped (both cores start with
/// last_seen = 1).
type Simulation {
  Simulation(a: Core, b: Core, sequence_number: Int)
}

fn new_simulation() -> Simulation {
  Simulation(a: bootstrap(id_a), b: bootstrap(id_b), sequence_number: 1)
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

fn ingest(core: Core, sequenced: types.SequencedDocumentMessage) -> Core {
  case runtime_core.handle_sequenced(core, sequenced) {
    Ok(#(core, _)) -> core
    Error(error) ->
      panic as { "handle_sequenced failed: " <> string.inspect(error) }
  }
}

/// Broadcast one author's outbound operations through the sequencer: each is
/// stamped with the next SN and delivered to *both* cores in order (author acks
/// its own, the other applies it remotely).
fn broadcast(
  simulation: Simulation,
  author: String,
  outbound: List(wire.OutboundOperation),
) -> Simulation {
  list.fold(outbound, simulation, fn(simulation, out) {
    let sequence_number = simulation.sequence_number + 1
    let sequenced = sequenced_message(author, sequence_number, out)
    Simulation(
      a: ingest(simulation.a, sequenced),
      b: ingest(simulation.b, sequenced),
      sequence_number: sequence_number,
    )
  })
}

// Run a runtime_core directory command against one core and return the
// outbound it produced (panicking on error), leaving the caller to broadcast.
fn expect_ok(
  result: Result(
    #(Core, List(#(String, channel.ChannelEvent)), List(wire.OutboundOperation)),
    runtime_core.CoreError,
  ),
) -> #(Core, List(wire.OutboundOperation)) {
  case result {
    Ok(#(core, _events, outbound)) -> #(core, outbound)
    Error(error) ->
      panic as { "directory command failed: " <> string.inspect(error) }
  }
}

// ── single-client wiring smoke ───────────────────────────────────────────────

/// Attach a directory channel by pointing a root-map handle at it (the same
/// dependency-attach path the other channel tests use), then exercise a
/// subdirectory create + storage set and check the operation wire shape and
/// reads.
pub fn attached_directory_emits_operations_and_reads_test() -> Nil {
  let core =
    bootstrap(id_a)
    |> runtime_core.create_detached(directory_address, channel.InitDirectory)

  // Setting a handle to the directory in root attaches it (attach operation +
  // root set operation).
  let #(core, attach_outbound) =
    expect_ok(runtime_core.set(
      core,
      "root",
      "tree",
      handle.encode_handle(directory_address),
    ))
  attach_outbound |> list.length |> expect.to_equal(2)

  // Create /surveys under the (now attached) directory root.
  let assert #(core, [create_operation]) =
    expect_ok(runtime_core.directory_create_subdirectory(
      core,
      directory_address,
      "/",
      "surveys",
    ))
  let encoded = json.to_string(create_operation.contents)
  encoded |> string.contains("\"type\":\"dirCreateSub\"") |> expect.to_be_true()
  encoded |> string.contains("\"name\":\"surveys\"") |> expect.to_be_true()
  encoded |> string.contains("\"mid\"") |> expect.to_be_true()

  runtime_core.directory_subdirectories(core, directory_address, "/")
  |> expect.to_equal(["surveys"])

  // Set a benchmark reading in /surveys.
  let assert #(core, [set_operation]) =
    expect_ok(runtime_core.directory_set(
      core,
      directory_address,
      "/surveys",
      "BM-17",
      json.string("recorded"),
    ))
  json.to_string(set_operation.contents)
  |> string.contains("\"type\":\"dirSet\"")
  |> expect.to_be_true()

  runtime_core.directory_get(core, directory_address, "/surveys", "BM-17")
  |> expect.to_equal(Ok(json.string("recorded")))
}

pub fn directory_set_attaches_handle_dependencies_test() -> Nil {
  let core =
    bootstrap(id_a)
    |> runtime_core.create_detached(directory_address, channel.InitDirectory)
  let #(core, _) =
    expect_ok(runtime_core.set(
      core,
      "root",
      "tree",
      handle.encode_handle(directory_address),
    ))
  let core = runtime_core.create_detached(core, "document", channel.InitJsonOt)

  let assert #(_core, [attach_operation, set_operation]) =
    expect_ok(runtime_core.directory_set(
      core,
      directory_address,
      "/",
      "config",
      handle.encode_handle("document"),
    ))

  json.to_string(attach_operation.contents)
  |> string.contains("\"type\":\"attach\"")
  |> expect.to_be_true()
  json.to_string(set_operation.contents)
  |> string.contains("\"type\":\"dirSet\"")
  |> expect.to_be_true()
}

/// A directory summary survives a JSON snapshot round-trip through the
/// channel codec (attach payload / summary blob `data`).
pub fn directory_snapshot_round_trips_test() -> Nil {
  // Build a small sequenced tree directly from the kernel: root note plus a
  // /plans child holding a reading.
  let state = directory_kernel.new()
  let assert Ok(#(state, _, operation, _)) =
    directory_kernel.set(state, "/", "root-note", json.string("v1"))
  let state = ack(state, operation)
  let assert Ok(#(state, _, Some(operation), _)) =
    directory_kernel.create_subdirectory(state, "/", "plans", 1)
  let state = ack(state, operation)
  let assert Ok(#(state, _, operation, _)) =
    directory_kernel.set(state, "/plans", "grade", json.string("2.1%"))
  let state = ack(state, operation)

  let snapshot = channel.DirectorySnapshot(directory_kernel.summary_tree(state))
  let encoded = channel.encode_snapshot(snapshot)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.DirectoryChannel),
    )
  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
}

/// Ack a directory operation locally, sequencing it at the next SN (test-only:
/// sequence_number numbers here are nominal, the round-trip only reads
/// sequenced storage).
fn ack(
  state: directory_kernel.DirectoryState,
  operation: directory_kernel.DirectoryOperation,
) -> directory_kernel.DirectoryState {
  let message_id = case directory_kernel.last_pending_message_id(state) {
    Ok(id) -> id
    Error(Nil) -> 0
  }
  case
    directory_kernel.ack_local(
      state,
      operation,
      directory_kernel.SequencedMeta(
        author: 1,
        sequence_number: message_id + 1,
        reference_sequence_number: 0,
        client_sequence_number: message_id,
      ),
    )
  {
    Ok(state) -> state
    Error(error) -> panic as { "ack failed: " <> string.inspect(error) }
  }
}

// ── two-client convergence ────────────────────────────────────────────────────

/// Two clients edit disjoint parts of the tree; after full delivery both
/// see the same sequenced tree.
pub fn two_clients_converge_test() -> Nil {
  let simulation = new_simulation()

  // A creates and attaches the directory, then both share it.
  let a =
    runtime_core.create_detached(
      simulation.a,
      directory_address,
      channel.InitDirectory,
    )
  let #(a, attach_out) =
    expect_ok(runtime_core.set(
      a,
      "root",
      "tree",
      handle.encode_handle(directory_address),
    ))
  let simulation = broadcast(Simulation(..simulation, a: a), id_a, attach_out)

  // A builds /surveys with a reading; B builds /plans with a reading.
  let #(a, out1) =
    expect_ok(runtime_core.directory_create_subdirectory(
      simulation.a,
      directory_address,
      "/",
      "surveys",
    ))
  let simulation = broadcast(Simulation(..simulation, a: a), id_a, out1)
  let #(a, out2) =
    expect_ok(runtime_core.directory_set(
      simulation.a,
      directory_address,
      "/surveys",
      "BM-17",
      json.string("recorded"),
    ))
  let simulation = broadcast(Simulation(..simulation, a: a), id_a, out2)

  let #(b, out3) =
    expect_ok(runtime_core.directory_create_subdirectory(
      simulation.b,
      directory_address,
      "/",
      "plans",
    ))
  let simulation = broadcast(Simulation(..simulation, b: b), id_b, out3)
  let #(b, out4) =
    expect_ok(runtime_core.directory_set(
      simulation.b,
      directory_address,
      "/plans",
      "grade",
      json.string("2.1%"),
    ))
  let simulation = broadcast(Simulation(..simulation, b: b), id_b, out4)

  // Both converge: same child order at root, same readings.
  let subs_a =
    runtime_core.directory_subdirectories(simulation.a, directory_address, "/")
  let subs_b =
    runtime_core.directory_subdirectories(simulation.b, directory_address, "/")
  subs_a |> expect.to_equal(subs_b)
  subs_a |> list.sort(string.compare) |> expect.to_equal(["plans", "surveys"])

  runtime_core.directory_get(
    simulation.a,
    directory_address,
    "/surveys",
    "BM-17",
  )
  |> expect.to_equal(Ok(json.string("recorded")))
  runtime_core.directory_get(
    simulation.b,
    directory_address,
    "/surveys",
    "BM-17",
  )
  |> expect.to_equal(Ok(json.string("recorded")))
  runtime_core.directory_get(simulation.a, directory_address, "/plans", "grade")
  |> expect.to_equal(runtime_core.directory_get(
    simulation.b,
    directory_address,
    "/plans",
    "grade",
  ))
}

/// Concurrent same-name create: both clients create `/logs` before seeing the
/// other's operation. They converge to a single `/logs`.
pub fn concurrent_same_name_create_converges_test() -> Nil {
  let simulation = new_simulation()
  let a =
    runtime_core.create_detached(
      simulation.a,
      directory_address,
      channel.InitDirectory,
    )
  let #(a, attach_out) =
    expect_ok(runtime_core.set(
      a,
      "root",
      "tree",
      handle.encode_handle(directory_address),
    ))
  let simulation = broadcast(Simulation(..simulation, a: a), id_a, attach_out)

  // Both author a create of /logs against the same base, THEN we deliver.
  let #(a, out_a) =
    expect_ok(runtime_core.directory_create_subdirectory(
      simulation.a,
      directory_address,
      "/",
      "logs",
    ))
  let #(b, out_b) =
    expect_ok(runtime_core.directory_create_subdirectory(
      simulation.b,
      directory_address,
      "/",
      "logs",
    ))
  let simulation = Simulation(..simulation, a: a, b: b)

  // Deliver A's create then B's create (both cores see both, in that order).
  let simulation = broadcast(simulation, id_a, out_a)
  let simulation = broadcast(simulation, id_b, out_b)

  runtime_core.directory_subdirectories(simulation.a, directory_address, "/")
  |> expect.to_equal(["logs"])
  runtime_core.directory_subdirectories(simulation.b, directory_address, "/")
  |> expect.to_equal(["logs"])
}
