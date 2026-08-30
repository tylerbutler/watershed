//// Multi-client convergence for `json_ot_kernel` against a simulated central
//// sequencer. This is the end-to-end proof that the kernel + a
//// kernel-agnostic (non-transforming) sequencer deliver OT: every replica that
//// receives the same total order of operations must land on byte-identical
//// `sequenced` documents.
////
//// The simulator mirrors `kernel_fuzz`'s delivery model: clients submit
//// operations optimistically (stamped with their last-delivered SN as
//// `reference_sequence_number`), a sequencer assigns a total order, and every
//// client delivers the whole log in SN order — acking its own operations,
//// `apply_remote`-ing others'. Each client keeps a single operation in flight
//// and composes later edits into a buffer, so a client's operations never
//// overlap each other's windows, but other clients' operations interleave
//// between them — exercising the concurrency-window transform, not just the
//// trivial single-operation case.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import qcheck
import watershed/fuzz/kernel_fuzz
import watershed/json_ot.{type JsonValue}
import watershed/json_ot_gen.{type Random}
import watershed/json_ot_kernel.{type JsonOtState, type JsonOtWireOperation} as kernel
import watershed/ot_client

const client_count = 3

fn ids() -> List(Int) {
  list.map(list.repeat(Nil, client_count), fn(_) { Nil })
  |> list.index_map(fn(_, i) { i })
}

/// One sequenced entry in the shared log.
type Entry {
  Entry(sequence_number: Int, author: Int, wire: JsonOtWireOperation)
}

type ClientSimulation {
  ClientSimulation(
    state: JsonOtState,
    /// Number of log entries this client has delivered (its SN cursor).
    delivered: Int,
    /// Operations submitted but not yet sequenced, in submission order.
    outbox: List(JsonOtWireOperation),
  )
}

type Simulation {
  Simulation(clients: List(ClientSimulation), log: List(Entry))
}

fn new_simulation(document: JsonValue) -> Simulation {
  Simulation(
    clients: ids()
      |> list.map(fn(_id) {
        ClientSimulation(kernel.from_value(document), delivered: 0, outbox: [])
      }),
    log: [],
  )
}

fn get(simulation: Simulation, id: Int) -> ClientSimulation {
  case list.drop(simulation.clients, id) {
    [c, ..] -> c
    [] -> panic as "client id out of range"
  }
}

fn put(simulation: Simulation, id: Int, c: ClientSimulation) -> Simulation {
  Simulation(
    ..simulation,
    clients: list.index_map(simulation.clients, fn(existing, i) {
      case i == id {
        True -> c
        False -> existing
      }
    }),
  )
}

/// The minimum sequence number (Fluid MSN): the oldest reference point any
/// operation still in the system may need. A live client contributes its
/// `delivered` cursor (the lowest `reference_sequence_number` it can still
/// stamp on a future operation), while an operation already in flight (queued
/// or sequenced-but-not-everywhere-delivered) pins the MSN down to the
/// `reference_sequence_number` it was authored against, since receivers still
/// need its concurrency window. A real sequencer derives this from the
/// `reference_sequence_number` clients stamp on their operations; the simulator
/// reconstructs it from global state.
fn minimum_sequence_number(simulation: Simulation) -> Int {
  let min_delivered =
    list.fold(simulation.clients, list.length(simulation.log), fn(acc, c) {
      int.min(acc, c.delivered)
    })
  // Operations still queued to send pin the MSN to their reference point.
  let with_outbox =
    list.fold(simulation.clients, min_delivered, fn(acc, c) {
      list.fold(c.outbox, acc, fn(acc, wire) {
        int.min(acc, wire.reference_sequence_number)
      })
    })
  // Sequenced operations not yet delivered by every client still need their
  // window.
  list.fold(simulation.log, with_outbox, fn(acc, entry) {
    case entry.sequence_number > min_delivered {
      True -> int.min(acc, entry.wire.reference_sequence_number)
      False -> acc
    }
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Commands
// ─────────────────────────────────────────────────────────────────────────────

/// A client authors an operation against its optimistic view. If the kernel
/// returns a wire operation (nothing was in flight) it is queued to send;
/// otherwise the edit was buffered and there is nothing to enqueue.
fn do_submit(
  simulation: Simulation,
  id: Int,
  random: Random,
) -> #(Simulation, Random) {
  let c = get(simulation, id)
  case kernel.view(c.state) {
    Error(e) -> panic as { "view failed: " <> string.inspect(e) }
    Ok(view_document) -> {
      let #(components, random) =
        json_ot_gen.generate_operation(view_document, random)
      case components {
        [] -> #(simulation, random)
        _ ->
          // reference_sequence_number = this client's last-delivered SN,
          // exactly what a live client stamps on the envelope.
          case kernel.submit(c.state, components, c.delivered) {
            Error(e) -> panic as { "submit failed: " <> string.inspect(e) }
            Ok(#(state, maybe_wire, _events)) -> {
              let outbox = case maybe_wire {
                Some(wire) -> list.append(c.outbox, [wire])
                None -> c.outbox
              }
              #(
                put(
                  simulation,
                  id,
                  ClientSimulation(..c, state: state, outbox: outbox),
                ),
                random,
              )
            }
          }
      }
    }
  }
}

/// The sequencer pulls the oldest queued operation from `id`'s outbox and
/// appends it to the total order.
fn do_sequence(simulation: Simulation, id: Int) -> Simulation {
  let c = get(simulation, id)
  case c.outbox {
    [] -> simulation
    [wire, ..rest] -> {
      let sequence_number = list.length(simulation.log) + 1
      let simulation =
        Simulation(
          ..simulation,
          log: list.append(simulation.log, [Entry(sequence_number, id, wire)]),
        )
      put(simulation, id, ClientSimulation(..c, outbox: rest))
    }
  }
}

/// A client delivers the next sequenced entry it hasn't seen: an ack for its
/// own operation (which may release a buffered operation onto its outbox), or
/// `apply_remote` for someone else's.
fn do_deliver_one(simulation: Simulation, id: Int) -> Simulation {
  let c = get(simulation, id)
  case list.drop(simulation.log, c.delivered) {
    [] -> simulation
    [entry, ..] -> {
      let min = minimum_sequence_number(simulation)
      case entry.author == id {
        True ->
          case
            kernel.ack_local(c.state, entry.wire, entry.sequence_number, min)
          {
            Error(e) -> panic as { "ack failed: " <> string.inspect(e) }
            Ok(#(state, _events)) -> {
              let #(state, released) = kernel.take_outbound(state)
              let outbox = case released {
                Some(wire) -> list.append(c.outbox, [wire])
                None -> c.outbox
              }
              put(
                simulation,
                id,
                ClientSimulation(
                  ..c,
                  state: state,
                  delivered: c.delivered + 1,
                  outbox: outbox,
                ),
              )
            }
          }
        False ->
          case
            kernel.apply_remote(c.state, entry.wire, entry.sequence_number, min)
          {
            Error(e) -> panic as { "apply_remote failed: " <> string.inspect(e) }
            Ok(#(state, _events)) ->
              put(
                simulation,
                id,
                ClientSimulation(..c, state: state, delivered: c.delivered + 1),
              )
          }
      }
    }
  }
}

/// Deliver every sequenced entry to every client (drain the whole log).
fn deliver_all(simulation: Simulation) -> Simulation {
  ids()
  |> list.fold(simulation, fn(simulation, id) {
    let target = list.length(simulation.log)
    do_deliver_until(simulation, id, target)
  })
}

fn do_deliver_until(
  simulation: Simulation,
  id: Int,
  target: Int,
) -> Simulation {
  case get(simulation, id).delivered >= target {
    True -> simulation
    False -> do_deliver_until(do_deliver_one(simulation, id), id, target)
  }
}

/// Sequence every queued operation from every client, in a rotating order so
/// authors interleave.
fn sequence_all(simulation: Simulation) -> Simulation {
  case list.all(simulation.clients, fn(c) { c.outbox == [] }) {
    True -> simulation
    False -> {
      let simulation =
        ids()
        |> list.fold(simulation, fn(simulation, id) {
          do_sequence(simulation, id)
        })
      sequence_all(simulation)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Driver
// ─────────────────────────────────────────────────────────────────────────────

/// Run a random schedule of submit/sequence/deliver, then synchronize and
/// assert convergence.
fn run(seed: Int, rounds: Int) -> Result(Nil, String) {
  let random = json_ot_gen.new_random(seed)
  let #(document, random) = json_ot_gen.random_document(random)
  let simulation = new_simulation(document)
  let #(simulation, _rng) = play_rounds(simulation, random, rounds)
  // Final synchronize: repeatedly sequence everything outstanding and deliver
  // to all. Acks release buffered operations into outboxes, so loop until the
  // system is fully settled — no queued operations and every client has
  // delivered the log.
  let simulation = drain(simulation)
  converged(simulation)
}

/// Sequence and deliver until nothing is outstanding: no queued operations in
/// any outbox and every client has delivered the entire log.
fn drain(simulation: Simulation) -> Simulation {
  let simulation = deliver_all(sequence_all(simulation))
  let settled =
    list.all(simulation.clients, fn(c) {
      c.outbox == [] && c.delivered == list.length(simulation.log)
    })
  case settled {
    True -> simulation
    False -> drain(simulation)
  }
}

fn play_rounds(
  simulation: Simulation,
  random: Random,
  rounds: Int,
) -> #(Simulation, Random) {
  case rounds <= 0 {
    True -> #(simulation, random)
    False -> {
      let #(simulation, random) = play_one(simulation, random)
      play_rounds(simulation, random, rounds - 1)
    }
  }
}

fn play_one(simulation: Simulation, random: Random) -> #(Simulation, Random) {
  let #(choice, random) = json_ot_gen.random_int(random, 10)
  let #(id, random) = json_ot_gen.random_int(random, client_count)
  case choice {
    // 0–4: author a local operation.
    n if n < 5 -> do_submit(simulation, id, random)
    // 5–6: sequence one client's oldest queued operation.
    n if n < 7 -> #(do_sequence(simulation, id), random)
    // 7–8: deliver one entry to a client.
    n if n < 9 -> #(do_deliver_one(simulation, id), random)
    // 9: sequence a batch, then deliver one to a client (mix).
    _ -> #(do_deliver_one(do_sequence(simulation, id), id), random)
  }
}

/// Every client's confirmed document must be byte-identical, with no operations
/// left in flight, buffered, or unsequenced.
fn converged(simulation: Simulation) -> Result(Nil, String) {
  let documents = list.map(simulation.clients, fn(c) { c.state.sequenced })
  let leftover_pending =
    list.any(simulation.clients, fn(c) { c.state.pending != ot_client.Idle })
  case documents {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case list.all(rest, fn(d) { d == first }), leftover_pending {
        True, False -> Ok(Nil)
        True, True -> Error("clients converged but pending ops remain")
        False, _ ->
          Error(
            "documents diverged:\n"
            <> string.inspect(
              list.map(simulation.clients, fn(c) { c.state.sequenced }),
            )
            <> "\nlog:\n"
            <> string.inspect(
              list.map(simulation.log, fn(e) {
                #(
                  e.sequence_number,
                  e.author,
                  e.wire.reference_sequence_number,
                  e.wire.components,
                )
              }),
            ),
          )
      }
  }
}

pub fn clients_converge_test() -> Nil {
  let config = kernel_fuzz.config_from_environment()
  qcheck.run(config, qcheck.uniform_int(), fn(seed) {
    case run(seed, 40) {
      Ok(Nil) -> Nil
      Error(detail) ->
        panic as {
          "convergence failure (seed="
          <> int.to_string(seed)
          <> "):\n"
          <> detail
        }
    }
  })
}
