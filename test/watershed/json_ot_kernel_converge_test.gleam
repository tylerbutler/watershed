//// Multi-client convergence for `json_ot_kernel` against a simulated central
//// sequencer. This is the end-to-end proof that the kernel + a
//// kernel-agnostic (non-transforming) sequencer deliver OT: every replica that
//// receives the same total order of ops must land on byte-identical
//// `sequenced` documents.
////
//// The simulator mirrors `kernel_fuzz`'s delivery model: clients submit ops
//// optimistically (stamped with their last-delivered SN as `ref_seq`), a
//// sequencer assigns a total order, and every client delivers the whole log in
//// SN order — acking its own ops, `apply_remote`-ing others'. Each client keeps
//// a single op in flight and composes later edits into a buffer, so a client's
//// ops never overlap each other's windows, but other clients' ops interleave
//// between them — exercising the concurrency-window transform, not just the
//// trivial single-op case.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import qcheck
import watershed/fuzz/kernel_fuzz
import watershed/json_ot.{type JsonValue}
import watershed/json_ot_gen.{type Rng}
import watershed/json_ot_kernel.{type JsonOtState, type JsonOtWireOp} as kernel

const client_count = 3

fn ids() -> List(Int) {
  list.map(list.repeat(Nil, client_count), fn(_) { Nil })
  |> list.index_map(fn(_, i) { i })
}

/// One sequenced entry in the shared log.
type Entry {
  Entry(seq: Int, author: Int, wire: JsonOtWireOp)
}

type ClientSim {
  ClientSim(
    state: JsonOtState,
    /// Number of log entries this client has delivered (its SN cursor).
    delivered: Int,
    /// Ops submitted but not yet sequenced, in submission order.
    outbox: List(JsonOtWireOp),
  )
}

type Sim {
  Sim(clients: List(ClientSim), log: List(Entry))
}

fn new_sim(doc: JsonValue) -> Sim {
  Sim(
    clients: ids()
      |> list.map(fn(id) {
        ClientSim(kernel.from_value(id, doc), delivered: 0, outbox: [])
      }),
    log: [],
  )
}

fn get(sim: Sim, id: Int) -> ClientSim {
  case list.drop(sim.clients, id) {
    [c, ..] -> c
    [] -> panic as "client id out of range"
  }
}

fn put(sim: Sim, id: Int, c: ClientSim) -> Sim {
  Sim(
    ..sim,
    clients: list.index_map(sim.clients, fn(existing, i) {
      case i == id {
        True -> c
        False -> existing
      }
    }),
  )
}

/// The minimum sequence number (Fluid MSN): the oldest reference point any op
/// still in the system may need. A live client contributes its `delivered`
/// cursor (the lowest `ref_seq` it can still stamp on a future op), while an op
/// already in flight (queued or sequenced-but-not-everywhere-delivered) pins the
/// MSN down to the `ref_seq` it was authored against, since receivers still need
/// its concurrency window. A real sequencer derives this from the `ref_seq`
/// clients stamp on their ops; the simulator reconstructs it from global state.
fn msn(sim: Sim) -> Int {
  let min_delivered =
    list.fold(sim.clients, list.length(sim.log), fn(acc, c) {
      int.min(acc, c.delivered)
    })
  // Ops still queued to send pin the MSN to their reference point.
  let with_outbox =
    list.fold(sim.clients, min_delivered, fn(acc, c) {
      list.fold(c.outbox, acc, fn(acc, wire) { int.min(acc, wire.ref_seq) })
    })
  // Sequenced ops not yet delivered by every client still need their window.
  list.fold(sim.log, with_outbox, fn(acc, entry) {
    case entry.seq > min_delivered {
      True -> int.min(acc, entry.wire.ref_seq)
      False -> acc
    }
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Commands
// ─────────────────────────────────────────────────────────────────────────────

/// A client authors an op against its optimistic view. If the kernel returns a
/// wire op (nothing was in flight) it is queued to send; otherwise the edit was
/// buffered and there is nothing to enqueue.
fn do_submit(sim: Sim, id: Int, rng: Rng) -> #(Sim, Rng) {
  let c = get(sim, id)
  case kernel.view(c.state) {
    Error(e) -> panic as { "view failed: " <> string.inspect(e) }
    Ok(view_doc) -> {
      let #(components, rng) = json_ot_gen.gen_op(view_doc, rng)
      case components {
        [] -> #(sim, rng)
        _ ->
          // ref_seq = this client's last-delivered SN, exactly what a live
          // client stamps on the envelope.
          case kernel.submit(c.state, components, c.delivered) {
            Error(e) -> panic as { "submit failed: " <> string.inspect(e) }
            Ok(#(state, maybe_wire, _events)) -> {
              let outbox = case maybe_wire {
                Some(wire) -> list.append(c.outbox, [wire])
                None -> c.outbox
              }
              #(put(sim, id, ClientSim(..c, state: state, outbox: outbox)), rng)
            }
          }
      }
    }
  }
}

/// The sequencer pulls the oldest queued op from `id`'s outbox and appends it
/// to the total order.
fn do_sequence(sim: Sim, id: Int) -> Sim {
  let c = get(sim, id)
  case c.outbox {
    [] -> sim
    [wire, ..rest] -> {
      let seq = list.length(sim.log) + 1
      let sim = Sim(..sim, log: list.append(sim.log, [Entry(seq, id, wire)]))
      put(sim, id, ClientSim(..c, outbox: rest))
    }
  }
}

/// A client delivers the next sequenced entry it hasn't seen: an ack for its
/// own op (which may release a buffered op onto its outbox), or `apply_remote`
/// for someone else's.
fn do_deliver_one(sim: Sim, id: Int) -> Sim {
  let c = get(sim, id)
  case list.drop(sim.log, c.delivered) {
    [] -> sim
    [entry, ..] -> {
      let min = msn(sim)
      case entry.author == id {
        True ->
          case kernel.ack_local(c.state, entry.wire, entry.seq, min) {
            Error(e) -> panic as { "ack failed: " <> string.inspect(e) }
            Ok(#(state, _events)) -> {
              let #(state, released) = kernel.take_outbound(state)
              let outbox = case released {
                Some(wire) -> list.append(c.outbox, [wire])
                None -> c.outbox
              }
              put(
                sim,
                id,
                ClientSim(
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
            kernel.apply_remote(
              c.state,
              entry.wire,
              entry.seq,
              entry.author,
              min,
            )
          {
            Error(e) ->
              panic as { "apply_remote failed: " <> string.inspect(e) }
            Ok(#(state, _events)) ->
              put(
                sim,
                id,
                ClientSim(..c, state: state, delivered: c.delivered + 1),
              )
          }
      }
    }
  }
}

/// Deliver every sequenced entry to every client (drain the whole log).
fn deliver_all(sim: Sim) -> Sim {
  ids()
  |> list.fold(sim, fn(sim, id) {
    let target = list.length(sim.log)
    do_deliver_until(sim, id, target)
  })
}

fn do_deliver_until(sim: Sim, id: Int, target: Int) -> Sim {
  case get(sim, id).delivered >= target {
    True -> sim
    False -> do_deliver_until(do_deliver_one(sim, id), id, target)
  }
}

/// Sequence every queued op from every client, in a rotating order so authors
/// interleave.
fn sequence_all(sim: Sim) -> Sim {
  case list.all(sim.clients, fn(c) { c.outbox == [] }) {
    True -> sim
    False -> {
      let sim =
        ids()
        |> list.fold(sim, fn(sim, id) { do_sequence(sim, id) })
      sequence_all(sim)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Driver
// ─────────────────────────────────────────────────────────────────────────────

/// Run a random schedule of submit/sequence/deliver, then synchronize and
/// assert convergence.
fn run(seed: Int, rounds: Int) -> Result(Nil, String) {
  let rng = json_ot_gen.new_rng(seed)
  let #(doc, rng) = json_ot_gen.random_doc(rng)
  let sim = new_sim(doc)
  let #(sim, _rng) = play_rounds(sim, rng, rounds)
  // Final synchronize: repeatedly sequence everything outstanding and deliver
  // to all. Acks release buffered ops into outboxes, so loop until the system
  // is fully settled — no queued ops and every client has delivered the log.
  let sim = drain(sim)
  converged(sim)
}

/// Sequence and deliver until nothing is outstanding: no queued ops in any
/// outbox and every client has delivered the entire log.
fn drain(sim: Sim) -> Sim {
  let sim = deliver_all(sequence_all(sim))
  let settled =
    list.all(sim.clients, fn(c) {
      c.outbox == [] && c.delivered == list.length(sim.log)
    })
  case settled {
    True -> sim
    False -> drain(sim)
  }
}

fn play_rounds(sim: Sim, rng: Rng, rounds: Int) -> #(Sim, Rng) {
  case rounds <= 0 {
    True -> #(sim, rng)
    False -> {
      let #(sim, rng) = play_one(sim, rng)
      play_rounds(sim, rng, rounds - 1)
    }
  }
}

fn play_one(sim: Sim, rng: Rng) -> #(Sim, Rng) {
  let #(choice, rng) = json_ot_gen.rand_int(rng, 10)
  let #(id, rng) = json_ot_gen.rand_int(rng, client_count)
  case choice {
    // 0–4: author a local op.
    n if n < 5 -> do_submit(sim, id, rng)
    // 5–6: sequence one client's oldest queued op.
    n if n < 7 -> #(do_sequence(sim, id), rng)
    // 7–8: deliver one entry to a client.
    n if n < 9 -> #(do_deliver_one(sim, id), rng)
    // 9: sequence a batch, then deliver one to a client (mix).
    _ -> #(do_deliver_one(do_sequence(sim, id), id), rng)
  }
}

/// Every client's confirmed document must be byte-identical, with no ops left
/// in flight, buffered, or unsequenced.
fn converged(sim: Sim) -> Result(Nil, String) {
  let docs = list.map(sim.clients, fn(c) { c.state.sequenced })
  let leftover_pending =
    list.any(sim.clients, fn(c) {
      c.state.inflight != None || c.state.buffer != None
    })
  case docs {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case list.all(rest, fn(d) { d == first }), leftover_pending {
        True, False -> Ok(Nil)
        True, True -> Error("clients converged but pending ops remain")
        False, _ ->
          Error(
            "documents diverged:\n"
            <> string.inspect(
              list.map(sim.clients, fn(c) { c.state.sequenced }),
            )
            <> "\nlog:\n"
            <> string.inspect(
              list.map(sim.log, fn(e) {
                #(e.seq, e.author, e.wire.ref_seq, e.wire.components)
              }),
            ),
          )
      }
  }
}

pub fn clients_converge_test() {
  let config = kernel_fuzz.config_from_env()
  qcheck.run(config, qcheck.uniform_int(), fn(seed) {
    case run(seed, 40) {
      Ok(Nil) -> Nil
      Error(msg) ->
        panic as {
          "convergence failure (seed=" <> int.to_string(seed) <> "):\n" <> msg
        }
    }
  })
}
