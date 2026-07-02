//// qcheck properties for the map kernel (plan M1):
////
//// (a) convergence — clients processing the same sequenced op stream end up
////     with equal state, regardless of which ops were locally theirs and of
////     when they submitted them (maximally early vs. just-before-ack).
//// (b) ack transparency — acking your own ops never changes the optimistic
////     view.
//// (c) rebase equivalence — the optimistic view equals the sequenced state
////     with the pending ops replayed on top.

import gleam/json.{type Json}
import gleam/list
import gleam/option
import qcheck
import watershed/map_kernel.{type MapOp, type MapState, Clear, Delete, Set}
import startest/expect

const iterations = 1000

fn config() -> qcheck.Config {
  qcheck.default_config() |> qcheck.with_test_count(iterations)
}

// ─────────────────────────────────────────────────────────────────────────────
// Generators
// ─────────────────────────────────────────────────────────────────────────────

/// A small key space so ops actually collide.
fn key_from_int(n: Int) -> String {
  case n % 4 {
    0 -> "a"
    1 -> "b"
    2 -> "c"
    _ -> "d"
  }
}

fn value_from_int(n: Int) -> Json {
  json.int(n % 100)
}

/// Sets common, deletes less so, clears rare — mirrors real workloads while
/// still exercising clear semantics.
fn op_from_ints(kind: Int, key: Int, value: Int) -> MapOp {
  case kind % 10 {
    0 | 1 | 2 | 3 | 4 | 5 -> Set(key_from_int(key), value_from_int(value))
    6 | 7 | 8 -> Delete(key_from_int(key))
    _ -> Clear
  }
}

fn op_generator() -> qcheck.Generator(MapOp) {
  qcheck.tuple3(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(ints) { op_from_ints(ints.0, ints.1, ints.2) })
}

fn ops_generator() -> qcheck.Generator(List(MapOp)) {
  qcheck.generic_list(op_generator(), qcheck.small_non_negative_int())
}

/// A sequenced stream where each op is attributed to one of `client_count`
/// authors, identified by index.
fn attributed_stream_generator(
  client_count: Int,
) -> qcheck.Generator(List(#(Int, MapOp))) {
  qcheck.generic_list(
    qcheck.tuple2(qcheck.small_non_negative_int(), op_generator())
      |> qcheck.map(fn(pair) { #(pair.0 % client_count, pair.1) }),
    qcheck.small_non_negative_int(),
  )
}

// ─────────────────────────────────────────────────────────────────────────────
// Simulation helpers
// ─────────────────────────────────────────────────────────────────────────────

fn submit_local(state: MapState, op: MapOp) -> MapState {
  case op {
    Set(key, value) -> {
      let #(state, _, _) = map_kernel.set(state, key, value)
      state
    }
    Delete(key) -> {
      let #(state, _, _) = map_kernel.delete(state, key)
      state
    }
    Clear -> {
      let #(state, _, _) = map_kernel.clear(state)
      state
    }
  }
}

fn ack_or_panic(state: MapState, op: MapOp) -> MapState {
  case map_kernel.ack_local(state, op) {
    Ok(state) -> state
    Error(_) -> panic as "ack did not match pending queue"
  }
}

/// Client `me` submits all of its ops optimistically before anything is
/// sequenced (maximum concurrency), then processes the stream.
fn simulate_eager(stream: List(#(Int, MapOp)), me: Int) -> MapState {
  let submitted =
    list.fold(stream, map_kernel.new(), fn(state, item) {
      case item.0 == me {
        True -> submit_local(state, item.1)
        False -> state
      }
    })
  list.fold(stream, submitted, fn(state, item) {
    case item.0 == me {
      True -> ack_or_panic(state, item.1)
      False -> {
        let #(state, _) = map_kernel.apply_remote(state, item.1)
        state
      }
    }
  })
}

/// Client `me` submits each of its ops immediately before it is sequenced
/// (no concurrency window at all).
fn simulate_lazy(stream: List(#(Int, MapOp)), me: Int) -> MapState {
  list.fold(stream, map_kernel.new(), fn(state, item) {
    case item.0 == me {
      True -> submit_local(state, item.1) |> ack_or_panic(item.1)
      False -> {
        let #(state, _) = map_kernel.apply_remote(state, item.1)
        state
      }
    }
  })
}

/// A client that authored nothing and applies the whole stream remotely.
fn simulate_observer(stream: List(#(Int, MapOp))) -> MapState {
  list.fold(stream, map_kernel.new(), fn(state, item) {
    let #(state, _) = map_kernel.apply_remote(state, item.1)
    state
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// (a) Convergence
// ─────────────────────────────────────────────────────────────────────────────

pub fn convergence_across_authors_and_submit_timing_test() {
  qcheck.run(config(), attributed_stream_generator(2), fn(stream) {
    let observer = map_kernel.entries(simulate_observer(stream))
    map_kernel.entries(simulate_eager(stream, 0)) |> expect.to_equal(observer)
    map_kernel.entries(simulate_lazy(stream, 0)) |> expect.to_equal(observer)
    map_kernel.entries(simulate_eager(stream, 1)) |> expect.to_equal(observer)
    map_kernel.entries(simulate_lazy(stream, 1)) |> expect.to_equal(observer)
  })
}

pub fn convergence_with_three_clients_test() {
  qcheck.run(config(), attributed_stream_generator(3), fn(stream) {
    let observer = map_kernel.entries(simulate_observer(stream))
    map_kernel.entries(simulate_eager(stream, 0)) |> expect.to_equal(observer)
    map_kernel.entries(simulate_eager(stream, 1)) |> expect.to_equal(observer)
    map_kernel.entries(simulate_eager(stream, 2)) |> expect.to_equal(observer)
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// (b) Ack transparency
// ─────────────────────────────────────────────────────────────────────────────

pub fn acking_own_ops_never_changes_optimistic_view_test() {
  qcheck.run(config(), ops_generator(), fn(ops) {
    let state = list.fold(ops, map_kernel.new(), submit_local)
    let snapshot = map_kernel.entries(state)
    // Ack every submitted op in order; the view must be identical after
    // every single ack, not just at the end.
    list.fold(ops, state, fn(state, op) {
      let state = ack_or_panic(state, op)
      map_kernel.entries(state) |> expect.to_equal(snapshot)
      state
    })
    Nil
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// (c) Rebase equivalence
// ─────────────────────────────────────────────────────────────────────────────

/// Replay the pending queue as if it were sequenced on top of the sequenced
/// data, with no pending overlay.
fn replay_pending(state: MapState) -> MapState {
  let base = map_kernel.MapState(..state, pending: [])
  list.fold(state.pending, base, fn(state, entry) {
    case entry {
      map_kernel.PendingLifetime(key, sets) ->
        list.fold(sets, state, fn(state, value) {
          let #(state, _) = map_kernel.apply_remote(state, Set(key, value))
          state
        })
      map_kernel.PendingDelete(key) -> {
        let #(state, _) = map_kernel.apply_remote(state, Delete(key))
        state
      }
      map_kernel.PendingClear -> {
        let #(state, _) = map_kernel.apply_remote(state, Clear)
        state
      }
    }
  })
}

pub fn optimistic_view_equals_sequenced_plus_replayed_pending_test() {
  qcheck.run(
    config(),
    qcheck.tuple2(ops_generator(), ops_generator()),
    fn(pair) {
      let #(remote_ops, local_ops) = pair
      // Build up sequenced state remotely, then layer pending local ops.
      let state =
        list.fold(remote_ops, map_kernel.new(), fn(state, op) {
          let #(state, _) = map_kernel.apply_remote(state, op)
          state
        })
      let state = list.fold(local_ops, state, submit_local)
      map_kernel.entries(state)
      |> expect.to_equal(map_kernel.entries(replay_pending(state)))
    },
  )
}

/// get/has agree with entries for every key in play.
pub fn point_reads_agree_with_iteration_test() {
  qcheck.run(
    config(),
    qcheck.tuple2(ops_generator(), ops_generator()),
    fn(pair) {
      let #(remote_ops, local_ops) = pair
      let state =
        list.fold(remote_ops, map_kernel.new(), fn(state, op) {
          let #(state, _) = map_kernel.apply_remote(state, op)
          state
        })
      let state = list.fold(local_ops, state, submit_local)
      let entries = map_kernel.entries(state)
      list.each(["a", "b", "c", "d"], fn(key) {
        let from_entries =
          list.find(entries, fn(entry) { entry.0 == key })
          |> option.from_result
          |> option.map(fn(entry) { entry.1 })
        map_kernel.get(state, key) |> expect.to_equal(from_entries)
        map_kernel.has(state, key)
        |> expect.to_equal(from_entries != option.None)
      })
    },
  )
}
