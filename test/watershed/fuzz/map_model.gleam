//// `KernelModel` for the map kernel. The oracle folds the sequenced operation
//// log through `apply_remote` alone (last-writer-wins by log order) — an
//// independent computation from the kernel's incremental sequenced/pending
//// split, so a convergence bug that "agrees on the wrong answer" still gets
//// caught. The `check` hook enforces rebase equivalence: the optimistic view
//// must always equal the sequenced state with pending operations replayed on
//// top, ported from the existing property test's `replay_pending`.

import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import qcheck
import watershed/fuzz/kernel_fuzz.{
  type KernelModel, type LogEntry, Capabilities, KernelModel,
}
import watershed/map_kernel.{
  type MapOperation, type MapState, Clear, Delete, PendingClear, PendingDelete,
  PendingLifetime, Set,
}

/// `MapOperation` carries a `Json` payload for `Set`, so it gets its own small
/// tag + fields shape rather than reusing `Command`'s tag (which only knows
/// about `Command`, not `MapOperation`'s constructors).
fn operation_to_json(operation: MapOperation) -> Json {
  case operation {
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

fn operation_decoder() -> decode.Decoder(MapOperation) {
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

/// A small key space so operations actually collide, matching the property
/// test.
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
fn operation_from_ints(kind: Int, key: Int, value: Int) -> MapOperation {
  case kind % 10 {
    0 | 1 | 2 | 3 | 4 | 5 -> Set(key_from_int(key), value_from_int(value))
    6 | 7 | 8 -> Delete(key_from_int(key))
    _ -> Clear
  }
}

fn operation_generator() -> qcheck.Generator(MapOperation) {
  qcheck.tuple3(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
  )
  |> qcheck.map(fn(ints) { operation_from_ints(ints.0, ints.1, ints.2) })
}

fn submit(
  state: MapState,
  operation: MapOperation,
  _meta: kernel_fuzz.SubmitMeta,
) -> #(MapState, option.Option(MapOperation)) {
  case operation {
    Set(key, value) -> {
      let #(state, _, _) = map_kernel.set(state, key, value)
      #(state, Some(operation))
    }
    Delete(key) -> {
      let #(state, _, _) = map_kernel.delete(state, key)
      #(state, Some(operation))
    }
    Clear -> {
      let #(state, _, _) = map_kernel.clear(state)
      #(state, Some(operation))
    }
  }
}

fn apply_remote(
  state: MapState,
  operation: MapOperation,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(MapState, String) {
  let #(state, _) = map_kernel.apply_remote(state, operation)
  Ok(state)
}

fn ack_local(
  state: MapState,
  operation: MapOperation,
  _meta: kernel_fuzz.SequencedMeta,
) -> Result(MapState, String) {
  case map_kernel.ack_local(state, operation) {
    Ok(state) -> Ok(state)
    Error(map_kernel.UnexpectedAck(_, detail)) -> Error(detail)
  }
}

fn oracle(entries: List(LogEntry(MapOperation))) -> List(#(String, Json)) {
  list.fold(
    kernel_fuzz.log_operations(entries),
    map_kernel.new(),
    fn(state, item) {
      let #(state, _) = map_kernel.apply_remote(state, item.1)
      state
    },
  )
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
/// `map_kernel.entries`), so acking one of several pending operations can move
/// it from the "pending" bucket to the "sequenced" bucket and thereby reorder
/// `entries()` relative to other still-pending keys, with no change in content.
/// Sort by key so the ack-transparency check sees through that.
fn canonicalize(entries: List(#(String, Json))) -> List(#(String, Json)) {
  list.sort(entries, fn(a, b) { string.compare(a.0, b.0) })
}

/// Summary round-trip: a fresh client sees exactly the sequenced entries a
/// summary snapshot would capture, in the same insertion order — no pending
/// local edits carry over (client 0, the summary source, never authors any).
fn load_from_synced(state: MapState, _id: Int) -> MapState {
  map_kernel.from_sequenced(map_kernel.sequenced_entries(state))
}

pub fn model() -> KernelModel(MapState, MapOperation, List(#(String, Json))) {
  KernelModel(
    name: "map",
    init: fn(_id) { map_kernel.new() },
    submit: submit,
    apply_remote: apply_remote,
    ack_local: ack_local,
    observe: map_kernel.entries,
    gen_operation: operation_generator(),
    check: Some(check_rebase_equivalence),
    canonicalize: Some(canonicalize),
    ack_preserves_view: True,
    operation_to_json: operation_to_json,
    operation_decoder: operation_decoder(),
    capabilities: Capabilities(
      load_from_synced: Some(load_from_synced),
      oracle: Some(oracle),
      rollback: None,
      resubmit: None,
      apply_stashed: None,
      react: None,
      remove_member: None,
    ),
  )
}
