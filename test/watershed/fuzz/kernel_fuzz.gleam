//// Pure fuzz harness core (F1): the pieces every ported kernel plugs into.
////
//// `KernelModel` is what a kernel supplies (init/submit/apply_remote/
//// ack_local/observe + optional capabilities). `Sim`/`Client` are a pure
//// server + clients with an inbox/log split so "submitted but not yet
//// sequenced" is an explicit, reachable state instead of the eager/lazy
//// degenerate schedules the old property tests hard-coded. `Command` is the
//// data the fuzzer generates and shrinks; `run_script` interprets a script
//// and validates convergence (and the oracle, if supplied) at every
//// `Synchronize`.
////
//// F1 supports `ClientOp` / `Sequence` / `Deliver` / `Synchronize`; F2 adds
//// `AddClient` (summary joins via `load_from_synced`); F3 adds
//// `Disconnect` / `Reconnect` (resend-queue semantics) and the
//// capability-gated `RollbackOp` / `StashedOp`; F4 adds `FUZZ_SEED` /
//// `FUZZ_ITERATIONS` env config (`config_from_env`) and JSON failure
//// fixtures (`dump_failure` / `script_decoder`) so a captured failing
//// script survives as a permanent regression test with no transcription.
////
//// The interpreter is written against `Result(Sim, String)` internally
//// (`try_run_script`) so tests can assert on a specific failure without
//// depending on panic capture; `run_script` panics on `Error` (after
//// dumping the failure to a JSON fixture), which is what makes qcheck
//// shrink and report the failing script.

import envoy
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import qcheck
import simplifile

// ─────────────────────────────────────────────────────────────────────────────
// Kernel model
// ─────────────────────────────────────────────────────────────────────────────

/// Metadata threaded into `submit` from day one. Counter and map ignore it;
/// claims (and later CAS-style consensus kernels) must compute an op's
/// `ref_seq` at submit time from the submitting client's delivered cursor,
/// which is exactly `last_seen_seq` (the sequence number of the last op this
/// client has processed — server SNs are 1-based log positions, so a client
/// that has delivered N ops has last seen SN N; 0 before it has seen any).
pub type SubmitMeta {
  SubmitMeta(last_seen_seq: Int)
}

/// Metadata threaded through `apply_remote`/`ack_local` from day one. Counter
/// and map ignore it; pact-map and ordered-collection (later milestones)
/// resolve ops against the connected-client quorum, so the signature is
/// right from F1 rather than retrofitted later.
pub type SequencedMeta {
  SequencedMeta(
    client_id: Int,
    sequence_number: Int,
    min_sequence_number: Int,
    connected_clients: List(Int),
  )
}

/// Optional per-kernel capabilities. Fields unused before their milestone
/// (`load_from_synced` is F2, `rollback`/`apply_stashed` are F3) are `None`.
pub type Capabilities(state, op, view) {
  Capabilities(
    // Builds a joining client's state from client 0's caught-up state (a
    // summary round trip). The second argument is the NEW client's identity
    // (its index, fresh and never reused — see `add_client`); replica-
    // identified kernels (pn_counter) must load the summary under the
    // joiner's own identity, not the summarizer's. Identity-free kernels
    // ignore it.
    load_from_synced: Option(fn(state, Int) -> state),
    oracle: Option(fn(List(#(Int, op))) -> view),
    rollback: Option(fn(state, op) -> state),
    // Re-applies a stashed op, returning the (possibly rewritten) op to
    // route onto the wire — mirroring `submit`, which may also rewrite.
    // Kernels whose wire ops carry content computed at apply time (a
    // pn_counter delta, or a remove's observed cursor) must hand back the
    // rewritten op or every peer would receive an unusable one; kernels
    // without that need return the op unchanged.
    apply_stashed: Option(fn(state, op, SubmitMeta) -> #(state, op)),
  )
}

pub type KernelModel(state, op, view) {
  KernelModel(
    name: String,
    // Build a client's initial state from its identity: the client's index,
    // stable for the sim's lifetime and never reused across `AddClient`
    // joins. Replica-identified kernels (pn_counter) derive their
    // `ReplicaId` from it; identity-free kernels (counter, map, claims)
    // ignore it — two PN replicas sharing an id silently lose increments
    // under max-merge, which is why the harness threads it from day one.
    init: fn(Int) -> state,
    // Optimistically apply a local op, returning the new state and the op to
    // route onto the wire — or `None` when the submit produces no op. Optimistic
    // kernels (counter, map) always return `Some(op)` unchanged. Consensus
    // kernels (claims) may return `None` (a synchronous no-op, e.g. a write-once
    // claim on an already-committed key, or a duplicate suppressed to keep the
    // kernel's one-pending-per-key invariant) and may return a *rewritten* op
    // whose contents were computed at submit time from `SubmitMeta` (claims
    // fills in `ref_seq` from the client's delivered cursor).
    submit: fn(state, op, SubmitMeta) -> #(state, Option(op)),
    apply_remote: fn(state, op, SequencedMeta) -> state,
    ack_local: fn(state, op, SequencedMeta) -> Result(state, String),
    observe: fn(state) -> view,
    gen_op: qcheck.Generator(op),
    // Optional per-model invariant, checked against every client's state
    // after every command (config-gated by whether the model supplies one).
    // Map's rebase equivalence (optimistic view ≡ sequenced + pending
    // replayed) is the motivating use; counter has none.
    check: Option(fn(state) -> Result(Nil, String)),
    // Canonicalizes a `view` for the "ack transparency" comparison only
    // (observe before/after `ack_local` of our own op). Some kernels
    // (map) deliberately render sequenced entries before pending ones, so
    // acking one of several pending ops can reorder `entries()` without
    // changing its content — `None` compares raw views; map supplies a
    // sort-by-key so that reordering isn't mistaken for a lost/changed
    // value.
    canonicalize: Option(fn(view) -> view),
    // Whether acking one's own op leaves `observe` unchanged. True for
    // optimistic kernels (counter/map show the value at submit, so the ack only
    // retires pending). False for non-optimistic consensus kernels (claims:
    // reads are committed-only, so acking a *winning* claim first makes it
    // visible — a legitimate view change, not a bug). Gates the ack-transparency
    // assertion in `deliver_one`; convergence and the oracle still validate
    // claims fully at every `Synchronize`.
    ack_preserves_view: Bool,
    // F4: reproduction DX. Every op must be JSON-round-trippable so a
    // shrunk failing script can be dumped to `test/fixtures/fuzz_failures/`
    // and replayed later with no transcription (see `dump_failure` and
    // `script_decoder`).
    op_to_json: fn(op) -> Json,
    op_decoder: Decoder(op),
    capabilities: Capabilities(state, op, view),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Simulator
// ─────────────────────────────────────────────────────────────────────────────

pub type Client(state, op) {
  Client(state: state, connected: Bool, resend: List(op), delivered: Int)
}

pub type Sim(state, op) {
  Sim(
    inbox: List(#(Int, op)),
    log: List(#(Int, op)),
    clients: List(Client(state, op)),
  )
}

fn new_sim(
  model: KernelModel(state, op, view),
  client_count: Int,
) -> Sim(state, op) {
  Sim(
    inbox: [],
    log: [],
    clients: list.repeat(Nil, client_count)
      |> list.index_map(fn(_, id) { Client(model.init(id), True, [], 0) }),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Commands
// ─────────────────────────────────────────────────────────────────────────────

/// The command language the fuzzer generates. F1 covers the four rows the
/// plan tags `F1`; F2 adds `AddClient`; F3 adds `Disconnect`/`Reconnect`
/// and the capability-gated `RollbackOp`/`StashedOp`.
pub type Command(op) {
  /// `submit` locally; push the op to the inbox if this client is
  /// connected, else to its `resend` queue (mirroring a disconnected
  /// client trying to send).
  ClientOp(client: Int, op: op)
  /// Move up to `n` ops from the inbox to the log, oldest first.
  Sequence(n: Int)
  /// Advance one client's cursor by up to `n` log entries.
  Deliver(client: Int, n: Int)
  /// Sequence everything, deliver everything to every client, then validate.
  Synchronize
  /// Fully deliver client 0's backlog, then join a new connected client
  /// built from `capabilities.load_from_synced(client_0.state, new_id)` —
  /// a summary round trip under the joiner's own fresh identity. Cursor
  /// starts at the log end, matching a client that just
  /// loaded a snapshot and has nothing more to catch up on. Errors loudly
  /// (rather than a silent no-op) when the model has no `load_from_synced`
  /// capability, since that is always a harness/model wiring gap.
  AddClient
  /// Disconnect a client: its in-flight inbox entries (submitted, not yet
  /// sequenced) move to its `resend` queue in order and never reach the
  /// log; already-sequenced entries are unaffected. The client keeps
  /// delivering/observing its own state; it's just excluded from
  /// convergence checks and can no longer reach the server.
  Disconnect(client: Int)
  /// Reconnect a disconnected client and resubmit its `resend` queue to the
  /// inbox, in order, clearing the queue.
  Reconnect(client: Int)
  /// `submit` locally, then immediately `capabilities.rollback` — the op
  /// never reaches the inbox/server. Errors loudly when the model has no
  /// `rollback` capability, rather than silently no-op-ing.
  RollbackOp(client: Int, op: op)
  /// Apply `op` via `capabilities.apply_stashed` (as if resuming a stashed
  /// local op after reconnect) instead of `submit`, then route the op it
  /// returned (possibly a rewrite of the generated one) to the inbox/resend
  /// queue exactly like `ClientOp`. Errors loudly when the model has no
  /// `apply_stashed` capability.
  StashedOp(client: Int, op: op)
}

// ─────────────────────────────────────────────────────────────────────────────
// Interpreter
// ─────────────────────────────────────────────────────────────────────────────

fn client_index(client: Int, client_count: Int) -> Int {
  let m = client % client_count
  case m < 0 {
    True -> m + client_count
    False -> m
  }
}

fn update_client(
  sim: Sim(state, op),
  index: Int,
  f: fn(Client(state, op)) -> Client(state, op),
) -> Sim(state, op) {
  let clients =
    list.index_map(sim.clients, fn(client, i) {
      case i == index {
        True -> f(client)
        False -> client
      }
    })
  Sim(..sim, clients: clients)
}

fn get_client(sim: Sim(state, op), index: Int) -> Client(state, op) {
  case list.take(sim.clients, index + 1) |> list.last {
    Ok(client) -> client
    Error(_) -> panic as "client index out of range"
  }
}

fn connected_indices(sim: Sim(state, op)) -> List(Int) {
  list.index_map(sim.clients, fn(client, i) { #(i, client) })
  |> list.filter_map(fn(pair) {
    case pair.1.connected {
      True -> Ok(pair.0)
      False -> Error(Nil)
    }
  })
}

fn meta_for(sim: Sim(state, op), sequence_number: Int) -> SequencedMeta {
  let author = case list.take(sim.log, sequence_number) |> list.last {
    Ok(item) -> item.0
    Error(_) -> panic as "meta requested for an unsequenced op"
  }
  let connected = connected_indices(sim)
  let min_delivered =
    list.fold(connected, sequence_number, fn(acc, index) {
      let client = get_client(sim, index)
      case client.delivered < acc {
        True -> client.delivered
        False -> acc
      }
    })
  SequencedMeta(
    client_id: author,
    sequence_number: sequence_number,
    min_sequence_number: min_delivered,
    connected_clients: connected,
  )
}

/// Deliver `log[client.delivered]` (0-indexed) to `client`: `ack_local` if
/// the client authored it, else `apply_remote`. An `ack_local` error is
/// always a real kernel bug — per-client submission order is preserved
/// through inbox → log → delivery, so the FIFO-ack assumption holds by
/// construction.
fn deliver_one(
  model: KernelModel(state, op, view),
  sim: Sim(state, op),
  index: Int,
) -> Result(Sim(state, op), String) {
  let client = get_client(sim, index)
  case client.delivered >= list.length(sim.log) {
    True -> Ok(sim)
    False -> {
      let assert Ok(#(author, op)) =
        list.take(sim.log, client.delivered + 1) |> list.last
      let meta = meta_for(sim, client.delivered + 1)
      case author == index {
        True -> {
          let before = model.observe(client.state)
          case model.ack_local(client.state, op, meta) {
            Error(detail) ->
              Error(
                "ack_local rejected op for client "
                <> int.to_string(index)
                <> " at sequence number "
                <> int.to_string(meta.sequence_number)
                <> ": "
                <> detail,
              )
            Ok(new_state) -> {
              let advanced =
                update_client(sim, index, fn(client) {
                  Client(
                    ..client,
                    state: new_state,
                    delivered: client.delivered + 1,
                  )
                })
              // Non-optimistic kernels (claims) legitimately change `observe`
              // when acking a winning op, so they opt out of this assertion.
              case model.ack_preserves_view {
                False -> Ok(advanced)
                True -> {
                  let after = model.observe(new_state)
                  let #(canon_before, canon_after) = case model.canonicalize {
                    None -> #(before, after)
                    Some(canonicalize) -> #(
                      canonicalize(before),
                      canonicalize(after),
                    )
                  }
                  case canon_after == canon_before {
                    False ->
                      Error(
                        "ack transparency violated for client "
                        <> int.to_string(index)
                        <> ": observe changed from "
                        <> string.inspect(before)
                        <> " to "
                        <> string.inspect(after)
                        <> " across an ack_local of our own op",
                      )
                    True -> Ok(advanced)
                  }
                }
              }
            }
          }
        }
        False ->
          Ok(
            update_client(sim, index, fn(client) {
              Client(
                ..client,
                state: model.apply_remote(client.state, op, meta),
                delivered: client.delivered + 1,
              )
            }),
          )
      }
    }
  }
}

fn deliver_n(
  model: KernelModel(state, op, view),
  sim: Sim(state, op),
  index: Int,
  n: Int,
) -> Result(Sim(state, op), String) {
  case n <= 0 {
    True -> Ok(sim)
    False -> {
      use sim <- result.try(deliver_one(model, sim, index))
      deliver_n(model, sim, index, n - 1)
    }
  }
}

fn sequence_n(sim: Sim(state, op), n: Int) -> Sim(state, op) {
  case n <= 0 {
    True -> sim
    False ->
      case sim.inbox {
        [] -> sim
        [head, ..rest] ->
          sequence_n(
            Sim(..sim, inbox: rest, log: list.append(sim.log, [head])),
            n - 1,
          )
      }
  }
}

fn deliver_all_connected(
  model: KernelModel(state, op, view),
  sim: Sim(state, op),
) -> Result(Sim(state, op), String) {
  list.try_fold(connected_indices(sim), sim, fn(sim, index) {
    let client = get_client(sim, index)
    let pending = list.length(sim.log) - client.delivered
    deliver_n(model, sim, index, pending)
  })
}

/// Validate convergence (every connected, fully-delivered client's `observe`
/// equals client 0's) and the oracle, if the model provides one. Only
/// called right after a full `Synchronize`, so client 0 has no pending
/// state and the oracle comparison is well-defined.
fn validate_convergence(
  model: KernelModel(state, op, view),
  sim: Sim(state, op),
) -> Result(Nil, String) {
  case connected_indices(sim) {
    [] -> Ok(Nil)
    [reference, ..rest] -> {
      let reference_client = get_client(sim, reference)
      let reference_view = model.observe(reference_client.state)
      use _ <- result.try(
        list.try_each(rest, fn(index) {
          let client = get_client(sim, index)
          let view = model.observe(client.state)
          case view == reference_view {
            True -> Ok(Nil)
            False ->
              Error(
                "convergence violated between client "
                <> int.to_string(reference)
                <> " and client "
                <> int.to_string(index)
                <> ": "
                <> string.inspect(reference_view)
                <> " != "
                <> string.inspect(view),
              )
          }
        }),
      )
      case model.capabilities.oracle {
        None -> Ok(Nil)
        Some(oracle) -> {
          let expected = oracle(sim.log)
          case reference_view == expected {
            True -> Ok(Nil)
            False ->
              Error(
                "oracle mismatch for client "
                <> int.to_string(reference)
                <> ": observed "
                <> string.inspect(reference_view)
                <> ", oracle expected "
                <> string.inspect(expected),
              )
          }
        }
      }
    }
  }
}

/// Run the model's optional per-state invariant hook (e.g. map's rebase
/// equivalence) against every client's current state.
fn validate_check(
  model: KernelModel(state, op, view),
  sim: Sim(state, op),
) -> Result(Nil, String) {
  case model.check {
    None -> Ok(Nil)
    Some(check) ->
      list.index_map(sim.clients, fn(client, i) { #(i, client) })
      |> list.try_each(fn(pair) {
        let #(index, client) = pair
        check(client.state)
        |> result.map_error(fn(detail) {
          "check hook failed for client "
          <> int.to_string(index)
          <> ": "
          <> detail
        })
      })
  }
}

/// Fully deliver client 0's backlog, then append a new connected client
/// built from `load_from_synced` applied to client 0's now-caught-up state
/// (a summary round trip: `from_sequenced(sequenced_entries(...))` for
/// map). The new client's cursor starts at the log end, same as client 0's.
fn add_client(
  model: KernelModel(state, op, view),
  sim: Sim(state, op),
) -> Result(Sim(state, op), String) {
  case model.capabilities.load_from_synced {
    None ->
      Error(
        "AddClient requires a load_from_synced capability, but model \""
        <> model.name
        <> "\" has none",
      )
    Some(load_from_synced) -> {
      let client0 = get_client(sim, 0)
      let pending = list.length(sim.log) - client0.delivered
      use sim <- result.try(deliver_n(model, sim, 0, pending))
      let client0 = get_client(sim, 0)
      // The joiner's identity is its index: clients are append-only and
      // never removed, so the current length is fresh and never reused.
      let new_id = list.length(sim.clients)
      let new_client =
        Client(
          state: load_from_synced(client0.state, new_id),
          connected: True,
          resend: [],
          delivered: list.length(sim.log),
        )
      Ok(Sim(..sim, clients: list.append(sim.clients, [new_client])))
    }
  }
}

/// Move `index`'s in-flight inbox entries (submitted, never sequenced) to
/// its `resend` queue, in order, and mark it disconnected. Other clients'
/// inbox entries and anything already in the log are untouched.
fn disconnect(sim: Sim(state, op), index: Int) -> Sim(state, op) {
  let #(mine, others) =
    list.partition(sim.inbox, fn(entry) { entry.0 == index })
  let sim = Sim(..sim, inbox: others)
  update_client(sim, index, fn(client) {
    Client(
      ..client,
      connected: False,
      resend: list.append(client.resend, list.map(mine, fn(entry) { entry.1 })),
    )
  })
}

/// Reconnect `index` and resubmit its `resend` queue to the inbox, in
/// order, clearing the queue.
fn reconnect(sim: Sim(state, op), index: Int) -> Sim(state, op) {
  let client = get_client(sim, index)
  let entries = list.map(client.resend, fn(op) { #(index, op) })
  let sim =
    update_client(sim, index, fn(client) {
      Client(..client, connected: True, resend: [])
    })
  Sim(..sim, inbox: list.append(sim.inbox, entries))
}

/// `submit` then immediately `capabilities.rollback` — the op never
/// touches the inbox. Errors loudly when the model has no `rollback`
/// capability.
fn rollback_op(
  model: KernelModel(state, op, view),
  sim: Sim(state, op),
  index: Int,
  op: op,
) -> Result(Sim(state, op), String) {
  case model.capabilities.rollback {
    None ->
      Error(
        "RollbackOp requires a rollback capability, but model \""
        <> model.name
        <> "\" has none",
      )
    Some(rollback) -> {
      let client = get_client(sim, index)
      let #(after_submit, maybe_op) =
        model.submit(client.state, op, SubmitMeta(client.delivered))
      // A submit that produced no op (a consensus-kernel no-op) has nothing to
      // roll back; otherwise roll back the op the submit actually routed.
      let rolled_back = case maybe_op {
        None -> after_submit
        Some(routed) -> rollback(after_submit, routed)
      }
      Ok(
        update_client(sim, index, fn(client) {
          Client(..client, state: rolled_back)
        }),
      )
    }
  }
}

/// Apply `op` via `capabilities.apply_stashed` instead of `submit`, then
/// route the op it returned — which may be a rewrite of the generated one,
/// mirroring `submit` — to the inbox/resend queue exactly like `ClientOp`.
/// Errors loudly when the model has no `apply_stashed` capability.
fn stashed_op(
  model: KernelModel(state, op, view),
  sim: Sim(state, op),
  index: Int,
  op: op,
) -> Result(Sim(state, op), String) {
  case model.capabilities.apply_stashed {
    None ->
      Error(
        "StashedOp requires an apply_stashed capability, but model \""
        <> model.name
        <> "\" has none",
      )
    Some(apply_stashed) -> {
      let client = get_client(sim, index)
      let #(new_state, routed) =
        apply_stashed(client.state, op, SubmitMeta(client.delivered))
      let sim =
        update_client(sim, index, fn(client) {
          Client(..client, state: new_state)
        })
      let sim = case client.connected {
        True -> Sim(..sim, inbox: list.append(sim.inbox, [#(index, routed)]))
        False ->
          update_client(sim, index, fn(client) {
            Client(..client, resend: list.append(client.resend, [routed]))
          })
      }
      Ok(sim)
    }
  }
}

fn synchronize(
  model: KernelModel(state, op, view),
  sim: Sim(state, op),
) -> Result(Sim(state, op), String) {
  let sim = sequence_n(sim, list.length(sim.inbox))
  use sim <- result.try(deliver_all_connected(model, sim))
  use _ <- result.try(validate_convergence(model, sim))
  Ok(sim)
}

fn interpret(
  model: KernelModel(state, op, view),
  sim: Sim(state, op),
  client_count: Int,
  command: Command(op),
) -> Result(Sim(state, op), String) {
  let result = case command {
    ClientOp(client, op) -> {
      let index = client_index(client, client_count)
      let existing = get_client(sim, index)
      let #(new_state, maybe_op) =
        model.submit(existing.state, op, SubmitMeta(existing.delivered))
      let sim =
        update_client(sim, index, fn(client) {
          Client(..client, state: new_state)
        })
      // Route the op the submit actually produced (which may be a rewritten
      // op), or nothing when the submit was a synchronous no-op.
      let sim = case maybe_op {
        None -> sim
        Some(routed) ->
          case existing.connected {
            True ->
              Sim(..sim, inbox: list.append(sim.inbox, [#(index, routed)]))
            False ->
              update_client(sim, index, fn(client) {
                Client(..client, resend: list.append(client.resend, [routed]))
              })
          }
      }
      Ok(sim)
    }
    Sequence(n) -> Ok(sequence_n(sim, n))
    Deliver(client, n) -> {
      let index = client_index(client, client_count)
      deliver_n(model, sim, index, n)
    }
    Synchronize -> synchronize(model, sim)
    AddClient -> add_client(model, sim)
    Disconnect(client) ->
      Ok(disconnect(sim, client_index(client, client_count)))
    Reconnect(client) -> Ok(reconnect(sim, client_index(client, client_count)))
    RollbackOp(client, op) ->
      rollback_op(model, sim, client_index(client, client_count), op)
    StashedOp(client, op) ->
      stashed_op(model, sim, client_index(client, client_count), op)
  }
  use sim <- result.try(result)
  use _ <- result.try(validate_check(model, sim))
  Ok(sim)
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON: script (de)serialization for failure fixtures (F4)
// ─────────────────────────────────────────────────────────────────────────────

/// JSON-encode one `Command`. `op_to_json` comes from the model, since `op`
/// is generic here.
pub fn command_to_json(
  op_to_json: fn(op) -> Json,
  command: Command(op),
) -> Json {
  case command {
    ClientOp(client, op) ->
      json.object([
        #("tag", json.string("ClientOp")),
        #("client", json.int(client)),
        #("op", op_to_json(op)),
      ])
    Sequence(n) ->
      json.object([#("tag", json.string("Sequence")), #("n", json.int(n))])
    Deliver(client, n) ->
      json.object([
        #("tag", json.string("Deliver")),
        #("client", json.int(client)),
        #("n", json.int(n)),
      ])
    Synchronize -> json.object([#("tag", json.string("Synchronize"))])
    AddClient -> json.object([#("tag", json.string("AddClient"))])
    Disconnect(client) ->
      json.object([
        #("tag", json.string("Disconnect")),
        #("client", json.int(client)),
      ])
    Reconnect(client) ->
      json.object([
        #("tag", json.string("Reconnect")),
        #("client", json.int(client)),
      ])
    RollbackOp(client, op) ->
      json.object([
        #("tag", json.string("RollbackOp")),
        #("client", json.int(client)),
        #("op", op_to_json(op)),
      ])
    StashedOp(client, op) ->
      json.object([
        #("tag", json.string("StashedOp")),
        #("client", json.int(client)),
        #("op", op_to_json(op)),
      ])
  }
}

/// JSON-encode a whole script.
pub fn script_to_json(
  op_to_json: fn(op) -> Json,
  script: List(Command(op)),
) -> Json {
  json.array(script, command_to_json(op_to_json, _))
}

/// Decode one `Command`. `Synchronize` is used as the placeholder zero-value
/// for an unrecognized tag (it is the one `Command(op)` constructor that
/// carries no `op`, so it works for any `op` type without needing a sample
/// value from the caller).
pub fn command_decoder(op_decoder: Decoder(op)) -> Decoder(Command(op)) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "ClientOp" -> {
      use client <- decode.field("client", decode.int)
      use op <- decode.field("op", op_decoder)
      decode.success(ClientOp(client, op))
    }
    "Sequence" -> {
      use n <- decode.field("n", decode.int)
      decode.success(Sequence(n))
    }
    "Deliver" -> {
      use client <- decode.field("client", decode.int)
      use n <- decode.field("n", decode.int)
      decode.success(Deliver(client, n))
    }
    "Synchronize" -> decode.success(Synchronize)
    "AddClient" -> decode.success(AddClient)
    "Disconnect" -> {
      use client <- decode.field("client", decode.int)
      decode.success(Disconnect(client))
    }
    "Reconnect" -> {
      use client <- decode.field("client", decode.int)
      decode.success(Reconnect(client))
    }
    "RollbackOp" -> {
      use client <- decode.field("client", decode.int)
      use op <- decode.field("op", op_decoder)
      decode.success(RollbackOp(client, op))
    }
    "StashedOp" -> {
      use client <- decode.field("client", decode.int)
      use op <- decode.field("op", op_decoder)
      decode.success(StashedOp(client, op))
    }
    other -> decode.failure(Synchronize, "Command tag " <> other)
  }
}

/// Decode a whole script.
pub fn script_decoder(op_decoder: Decoder(op)) -> Decoder(List(Command(op))) {
  decode.list(command_decoder(op_decoder))
}

// ─────────────────────────────────────────────────────────────────────────────
// Failure fixtures (F4): dump on failure, replay from disk
// ─────────────────────────────────────────────────────────────────────────────

/// Directory permanent regression fixtures live in. Populated by
/// `dump_failure`; every file here is replayed by the fixtures replay test
/// (see `test/watershed/fuzz_replay_test.gleam`).
pub const fixtures_dir = "test/fixtures/fuzz_failures"

/// Path `dump_failure` writes/overwrites for a given model. One fixture per
/// model name: the newest captured failure for that model is what's on
/// disk, matching upstream's `saveFailures` idea of resurfacing the latest
/// counterexample without hand transcription.
pub fn fixture_path(model_name: String) -> String {
  fixtures_dir <> "/" <> model_name <> "_failure.json"
}

/// Dump a failing script to `fixture_path(model.name)` as JSON: model name,
/// client count, the recorded failure detail, and the script itself. Called
/// from `run_script` right before it panics, so the file already holds the
/// final (most-shrunk) failing script by the time qcheck's shrink search
/// completes and the panic reaches the top of the test — no need to catch
/// the panic to capture it.
pub fn dump_failure(
  model: KernelModel(state, op, view),
  client_count: Int,
  script: List(Command(op)),
  detail: String,
) -> Result(String, simplifile.FileError) {
  let path = fixture_path(model.name)
  let payload =
    json.object([
      #("model", json.string(model.name)),
      #("client_count", json.int(client_count)),
      #("detail", json.string(detail)),
      #("script", script_to_json(model.op_to_json, script)),
    ])
  use _ <- result.try(simplifile.create_directory_all(fixtures_dir))
  use _ <- result.try(simplifile.write(path, json.to_string(payload)))
  Ok(path)
}

/// Interpret a script against a fresh `Sim` with `client_count` clients,
/// validating convergence (and the `check` hook, if supplied) after every
/// command, plus a final synchronize appended at the end of the script.
pub fn try_run_script(
  model: KernelModel(state, op, view),
  client_count: Int,
  script: List(Command(op)),
) -> Result(Nil, String) {
  let sim = new_sim(model, client_count)
  use sim <- result.try(
    list.try_fold(script, sim, fn(sim, command) {
      interpret(model, sim, client_count, command)
    }),
  )
  use _ <- result.try(synchronize(model, sim))
  Ok(Nil)
}

/// Same as `try_run_script`, but panics on `Error` — which is what makes
/// qcheck shrink and report the failing script (`string.inspect` of the
/// command list).
pub fn run_script(
  model: KernelModel(state, op, view),
  client_count: Int,
  script: List(Command(op)),
) -> Nil {
  case try_run_script(model, client_count, script) {
    Ok(Nil) -> Nil
    Error(detail) -> {
      let _ = dump_failure(model, client_count, script, detail)
      panic as detail
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Running the fuzzer
// ─────────────────────────────────────────────────────────────────────────────

/// `qcheck.Config` sized from `FUZZ_ITERATIONS` (default 200 — a fast
/// profile so plain `gleam test` stays quick) and seeded from `FUZZ_SEED` if
/// set (default: random). `just fuzz` overrides `FUZZ_ITERATIONS` to a much
/// larger deep-run count for CI/nightly-grade coverage.
///
/// Reproduction note: qcheck 1.x's `Seed` is an opaque type with no
/// accessor, so a failing run can't print "the seed that produced this" for
/// you to paste back in when `FUZZ_SEED` was unset. `FUZZ_SEED` still lets
/// you *pin* a seed up front to make a whole run reproducible end to end;
/// for after-the-fact reproduction of one specific failure regardless of
/// seed, use the JSON fixture `run_script` dumps to
/// `test/fixtures/fuzz_failures/` on failure (see `dump_failure`) and the
/// replay test that reads it back — that's the fallback this harness uses
/// instead of relying on a seed round-trip qcheck doesn't expose.
pub fn config_from_env() -> qcheck.Config {
  let test_count = case envoy.get("FUZZ_ITERATIONS") {
    Ok(value) ->
      case int.parse(value) {
        Ok(n) -> n
        Error(_) -> 200
      }
    Error(_) -> 200
  }
  let base = qcheck.default_config() |> qcheck.with_test_count(test_count)
  case envoy.get("FUZZ_SEED") {
    Ok(value) ->
      case int.parse(value) {
        Ok(n) -> base |> qcheck.with_seed(qcheck.seed(n))
        Error(_) -> base
      }
    Error(_) -> base
  }
}

/// Run `client_count`-client scripts drawn from `script_generator` against
/// `model`, using `config` (see `config_from_env` for the seeded/env-driven
/// default).
pub fn run(
  model: KernelModel(state, op, view),
  config: qcheck.Config,
  client_count: Int,
  script_generator: qcheck.Generator(List(Command(op))),
) -> Nil {
  qcheck.run(config, script_generator, fn(script) {
    run_script(model, client_count, script)
  })
}
