//// `KernelModel` for the map kernel. The oracle folds the sequenced op log
//// through `apply_remote` alone (last-writer-wins by log order) — an
//// independent computation from the kernel's incremental sequenced/pending
//// split, so a convergence bug that "agrees on the wrong answer" still gets
//// caught. The `check` hook enforces rebase equivalence: the optimistic
//// view must always equal the sequenced state with pending ops replayed on
//// top, ported from the existing property test's `replay_pending`.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import qcheck
import watershed/fuzz/kernel_fuzz.{type KernelModel, Capabilities, KernelModel}
import watershed/map_kernel.{
  type MapOp, type MapState, Clear, Delete, PendingClear, PendingDelete,
  PendingLifetime, Set,
}

/// `MapOp` carries a `Json` payload for `Set`, so it gets its own small tag
/// + fields shape rather than reusing `Command`'s tag (which only knows
/// about `Command`, not `MapOp`'s constructors).
fn op_to_json(op: MapOp) -> Json {
  case op {
    Set(key, value) ->
      json.object([
        #("tag", json.string("Set")),
        #("key", json.string(key)),
        #("value", value),
      ])
    Delete(key) ->
      json.object([#("tag", json.string("Delete")), #("key", json.string(key))])
    Clear -> json.object([#("tag", json.string("Clear"))])
  }
}

fn op_decoder() -> decode.Decoder(MapOp) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "Set" -> {
      use key <- decode.field("key", decode.string)
      use value <- decode.field("value", decode.int)
      decode.success(Set(key, json.int(value)))
    }
    "Delete" -> {
      use key <- decode.field("key", decode.string)
      decode.success(Delete(key))
    }
    _ -> decode.success(Clear)
  }
}

/// A small key space so ops actually collide, matching the property test.
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

/// Sets common, deletes less so, clears rare.
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

fn submit(state: MapState, op: MapOp, _meta: kernel_fuzz.SubmitMeta) -> MapState {
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

fn apply_remote(
  state: MapState,
  op: MapOp,
  _meta: kernel_fuzz.SequencedMeta,
) -> MapState {
  let #(state, _) = map_kernel.apply_remote(state, op)
  state
}

fn ack_local(
  state: MapState,
  op: MapOp,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(MapState, String) {
  case map_kernel.ack_local(state, op) {
    Ok(state) -> Ok(state)
    Error(map_kernel.UnexpectedAck(_, detail)) -> Error(detail)
  }
}

fn oracle(log: List(#(Int, MapOp))) -> List(#(String, Json)) {
  list.fold(log, map_kernel.new(), fn(state, item) {
    let #(state, _) = map_kernel.apply_remote(state, item.1)
    state
  })
  |> map_kernel.entries
}

/// Replay the pending queue as if it were sequenced on top of the sequenced
/// data, with no pending overlay — ported from the property test.
fn replay_pending(state: MapState) -> MapState {
  let base = map_kernel.MapState(..state, pending: [])
  list.fold(state.pending, base, fn(state, entry) {
    case entry {
      PendingLifetime(key, sets) ->
        list.fold(sets, state, fn(state, value) {
          let #(state, _) = map_kernel.apply_remote(state, Set(key, value))
          state
        })
      PendingDelete(key) -> {
        let #(state, _) = map_kernel.apply_remote(state, Delete(key))
        state
      }
      PendingClear -> {
        let #(state, _) = map_kernel.apply_remote(state, Clear)
        state
      }
    }
  })
}

fn check_rebase_equivalence(state: MapState) -> Result(Nil, String) {
  let optimistic = map_kernel.entries(state)
  let rebased = map_kernel.entries(replay_pending(state))
  case optimistic == rebased {
    True -> Ok(Nil)
    False ->
      Error(
        "optimistic view "
        <> string.inspect(optimistic)
        <> " does not equal sequenced-plus-replayed-pending "
        <> string.inspect(rebased),
      )
  }
}

/// Sequenced entries always render before pending ones (see
/// `map_kernel.entries`), so acking one of several pending ops can move it
/// from the "pending" bucket to the "sequenced" bucket and thereby reorder
/// `entries()` relative to other still-pending keys, with no change in
/// content. Sort by key so the ack-transparency check sees through that.
fn canonicalize(entries: List(#(String, Json))) -> List(#(String, Json)) {
  list.sort(entries, fn(a, b) { string.compare(a.0, b.0) })
}

/// Summary round-trip: a fresh client sees exactly the sequenced entries a
/// summary snapshot would capture, in the same insertion order — no pending
/// local edits carry over (client 0, the summary source, never authors any).
fn load_from_synced(state: MapState) -> MapState {
  map_kernel.from_sequenced(map_kernel.sequenced_entries(state))
}

pub fn model() -> KernelModel(MapState, MapOp, List(#(String, Json))) {
  KernelModel(
    name: "map",
    init: map_kernel.new,
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: map_kernel.entries,
    gen_op: op_generator(),
    check: Some(check_rebase_equivalence),
    canonicalize: Some(canonicalize),
    op_to_json: op_to_json,
    op_decoder: op_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: None,
      apply_stashed: None,
    ),
  )
}
