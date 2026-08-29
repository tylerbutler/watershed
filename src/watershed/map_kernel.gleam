//// Pure port of FluidFramework's `packages/dds/map/src/mapKernel.ts`.
////
//// There is no process and there are no side effects. Every operation returns
//// the new state with the events and the outbound op that it produced. The
//// runtime actor owns the sequencing work: the CSN, the RSN, and the ack
//// matching by `(client_id, csn)`. The kernel assumes only that the acks
//// arrive in submission order (FIFO). The TypeScript kernel makes the same
//// assumption in its reference-identity asserts.
////
//// The state is split the same way as in the TypeScript kernel:
//// - `sequenced`: the values that the server confirmed, with
////   `insertion_order`. The Gleam `Dict` type is unordered, but the TypeScript
////   kernel depends on the insertion-order iteration of the JavaScript `Map`
////   type.
//// - `pending`: the local optimistic changes that have no ack yet.
////   Consecutive sets to one key are collected into a "lifetime", so the
////   iteration order stays correct across the remote ops.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type MapState {
  MapState(
    sequenced: Dict(String, Json),
    insertion_order: List(String),
    pending: List(PendingEntry),
  )
}

pub type PendingEntry {
  /// One or more consecutive local sets to one key, oldest first. A delete or
  /// a clear ends the lifetime. A later set starts a new lifetime.
  PendingLifetime(key: String, sets: List(Json))
  PendingDelete(key: String)
  PendingClear
}

/// A map operation in its wire form, before the envelope and the encoding.
/// Those belong to the wire layer.
pub type MapOp {
  Set(key: String, value: Json)
  Delete(key: String)
  Clear
}

pub type MapEvent {
  /// `value: None` means that a delete or a clear removed the key.
  ValueChanged(
    key: String,
    previous_value: Option(Json),
    value: Option(Json),
    local: Bool,
  )
  Cleared(local: Bool)
}

/// The kernel returns this error when an ack does not agree with the pending
/// queue. The TypeScript kernel fails an assert here. The caller, which is the
/// runtime actor, must treat this error as fatal and crash. It must not
/// continue with divergent state.
pub type KernelError {
  UnexpectedAck(op: MapOp, detail: String)
}

pub fn new() -> MapState {
  MapState(sequenced: dict.new(), insertion_order: [], pending: [])
}

/// Build a state that contains sequenced data only, from the summary snapshot
/// entries. The function keeps the supplied insertion order. Use it to start a
/// connection from a stored summary, before you replay the deltas that follow
/// that summary. A snapshot that you load has no pending local edits.
pub fn from_sequenced(entries: List(#(String, Json))) -> MapState {
  let #(sequenced, order) =
    list.fold(entries, #(dict.new(), []), fn(acc, entry) {
      let #(sequenced, order) = acc
      let #(key, value) = entry
      // Guard against duplicate keys in a snapshot: keep the last value but the
      // first-seen position, matching JS-Map insertion semantics.
      let order = case dict.has_key(sequenced, key) {
        True -> order
        False -> [key, ..order]
      }
      #(dict.insert(sequenced, key, value), order)
    })
  MapState(
    sequenced: sequenced,
    insertion_order: list.reverse(order),
    pending: [],
  )
}

/// The sequenced entries in insertion order. This function ignores the pending
/// local edits. A summary snapshot captures this confirmed state.
pub fn sequenced_entries(state: MapState) -> List(#(String, Json)) {
  list.filter_map(state.insertion_order, fn(key) {
    case dict.get(state.sequenced, key) {
      Ok(value) -> Ok(#(key, value))
      Error(_) -> Error(Nil)
    }
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

/// An optimistic read: the sequenced data with the pending local changes over
/// it. The result is `Error(Nil)` when the map holds no value for the key.
pub fn get(state: MapState, key: String) -> Result(Json, Nil) {
  case latest_pending_for(state.pending, key) {
    Error(Nil) -> dict.get(state.sequenced, key)
    Ok(PendingLifetime(_, sets)) -> list.last(sets)
    Ok(PendingDelete(_)) | Ok(PendingClear) -> Error(Nil)
  }
}

pub fn has(state: MapState, key: String) -> Bool {
  result.is_ok(get(state, key))
}

pub fn size(state: MapState) -> Int {
  list.length(entries(state))
}

pub fn keys(state: MapState) -> List(String) {
  entries(state) |> list.map(fn(entry) { entry.0 })
}

/// The entries that are observable optimistically, in the order of the
/// TypeScript iterator. The sequenced keys come first, in insertion order, and
/// the function skips each key that has a pending delete or clear. The pending
/// lifetimes come after, and the function keeps only those that a later delete
/// or clear does not remove.
pub fn entries(state: MapState) -> List(#(String, Json)) {
  let sequenced_phase =
    list.filter_map(state.insertion_order, fn(key) {
      // A pending delete/clear means this key either disappears or re-appears
      // later at its lifetime's position, not here.
      case has_pending_delete_or_clear(state.pending, key) {
        True -> Error(Nil)
        False -> get(state, key) |> result.map(fn(value) { #(key, value) })
      }
    })

  let indexed = list.index_map(state.pending, fn(entry, i) { #(i, entry) })
  let pending_phase =
    list.filter_map(indexed, fn(pair) {
      let #(index, entry) = pair
      case entry {
        PendingLifetime(key, sets) -> {
          let last_dc = last_delete_or_clear_index(indexed, key)
          let survives = index > last_dc
          // If the key is in sequenced data and no delete/clear terminated
          // it, it was already iterated in the sequenced phase.
          let already_iterated =
            dict.has_key(state.sequenced, key) && last_dc == -1
          case survives && !already_iterated {
            True -> list.last(sets) |> result.map(fn(value) { #(key, value) })
            False -> Error(Nil)
          }
        }
        PendingDelete(_) | PendingClear -> Error(Nil)
      }
    })

  list.append(sequenced_phase, pending_phase)
}

// ─────────────────────────────────────────────────────────────────────────────
// Local operations (optimistic apply + outbound op)
// ─────────────────────────────────────────────────────────────────────────────

pub fn set(
  state: MapState,
  key: String,
  value: Json,
) -> #(MapState, List(MapEvent), MapOp) {
  let previous = get(state, key)
  // A new lifetime starts if there's no pending entry for the key, or the
  // latest one is a delete/clear (which terminates the prior lifetime).
  let pending = case latest_pending_for(state.pending, key) {
    Ok(PendingLifetime(_, _)) ->
      append_to_latest_lifetime(state.pending, key, value)
    Ok(PendingDelete(_)) | Ok(PendingClear) | Error(Nil) ->
      list.append(state.pending, [PendingLifetime(key, [value])])
  }
  #(
    MapState(..state, pending: pending),
    [ValueChanged(key, option.from_result(previous), Some(value), True)],
    Set(key, value),
  )
}

pub fn delete(
  state: MapState,
  key: String,
) -> #(MapState, List(MapEvent), MapOp) {
  let previous = get(state, key)
  let pending = list.append(state.pending, [PendingDelete(key)])
  // Speculative deletion still sends the op, but only emits if we locally
  // observed a value disappear.
  let events = case previous {
    Ok(value) -> [ValueChanged(key, Some(value), None, True)]
    Error(Nil) -> []
  }
  #(MapState(..state, pending: pending), events, Delete(key))
}

pub fn clear(state: MapState) -> #(MapState, List(MapEvent), MapOp) {
  let visible = entries(state)
  let pending = list.append(state.pending, [PendingClear])
  let events = [
    Cleared(True),
    ..list.map(visible, fn(entry) {
      ValueChanged(entry.0, Some(entry.1), None, True)
    })
  ]
  #(MapState(..state, pending: pending), events, Clear)
}

// ─────────────────────────────────────────────────────────────────────────────
// Remote operations
// ─────────────────────────────────────────────────────────────────────────────

/// Apply a sequenced op from another client. The kernel suppresses the events
/// when the pending local changes hide the remote change in the optimistic
/// view.
pub fn apply_remote(state: MapState, op: MapOp) -> #(MapState, List(MapEvent)) {
  case op {
    Set(key, value) -> {
      let previous = dict.get(state.sequenced, key) |> option.from_result
      let insertion_order = case dict.has_key(state.sequenced, key) {
        True -> state.insertion_order
        False -> list.append(state.insertion_order, [key])
      }
      let sequenced = dict.insert(state.sequenced, key, value)
      let events = case has_pending_for(state.pending, key) {
        True -> []
        False -> [ValueChanged(key, previous, Some(value), False)]
      }
      #(
        MapState(
          ..state,
          sequenced: sequenced,
          insertion_order: insertion_order,
        ),
        events,
      )
    }
    Delete(key) -> {
      let previous = dict.get(state.sequenced, key) |> option.from_result
      let sequenced = dict.delete(state.sequenced, key)
      let insertion_order =
        list.filter(state.insertion_order, fn(k) { k != key })
      let events = case has_pending_for(state.pending, key) {
        True -> []
        False -> [ValueChanged(key, previous, None, False)]
      }
      #(
        MapState(
          ..state,
          sequenced: sequenced,
          insertion_order: insertion_order,
        ),
        events,
      )
    }
    Clear -> {
      // Keys with any pending entry stay optimistically visible, so no
      // valueChanged is emitted for them.
      let deleted =
        list.filter_map(state.insertion_order, fn(key) {
          case has_pending_entry_for_key(state.pending, key) {
            True -> Error(Nil)
            False ->
              dict.get(state.sequenced, key)
              |> result.map(fn(value) { #(key, value) })
          }
        })
      let has_pending_clear =
        list.any(state.pending, fn(entry) { entry == PendingClear })
      let events = case has_pending_clear {
        True -> []
        False -> [
          Cleared(False),
          ..list.map(deleted, fn(entry) {
            ValueChanged(entry.0, Some(entry.1), None, False)
          })
        ]
      }
      #(MapState(..state, sequenced: dict.new(), insertion_order: []), events)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Acks (own ops coming back sequenced)
// ─────────────────────────────────────────────────────────────────────────────

/// Commit an acked local op, which moves it from `pending` to `sequenced`. The
/// acks must arrive in submission order. A mismatch means that the runtime
/// routed an ack for an op that the kernel never submitted, or that it routed
/// the acks out of order. Either condition is fatal.
///
/// An ack never emits an event. The optimistic view already showed the op at
/// submit time.
pub fn ack_local(state: MapState, op: MapOp) -> Result(MapState, KernelError) {
  case op {
    Clear ->
      // Ops ack in submission order, so by the time our clear is sequenced
      // every earlier pending entry has been acked: the clear must be at the
      // head of the queue.
      case state.pending {
        [PendingClear, ..rest] ->
          Ok(MapState(sequenced: dict.new(), insertion_order: [], pending: rest))
        _ -> Error(UnexpectedAck(op, "expected pending clear at queue head"))
      }
    Delete(key) ->
      case split_at_first_for_key(state.pending, key) {
        Ok(#(before, PendingDelete(_), after)) ->
          Ok(MapState(
            sequenced: dict.delete(state.sequenced, key),
            insertion_order: list.filter(state.insertion_order, fn(k) {
              k != key
            }),
            pending: list.append(before, after),
          ))
        Ok(#(_, PendingLifetime(_, _), _))
        | Ok(#(_, PendingClear, _))
        | Error(Nil) ->
          Error(UnexpectedAck(op, "expected pending delete for key " <> key))
      }
    Set(key, _) ->
      case split_at_first_for_key(state.pending, key) {
        Ok(#(before, PendingLifetime(_, [acked_value, ..remaining_sets]), after)) -> {
          // Commit the oldest pending set of the lifetime (FIFO, mirroring
          // the TS `keySets.shift()`); drop the lifetime once empty.
          let pending = case remaining_sets {
            [] -> list.append(before, after)
            _ ->
              list.append(before, [
                PendingLifetime(key, remaining_sets),
                ..after
              ])
          }
          let insertion_order = case dict.has_key(state.sequenced, key) {
            True -> state.insertion_order
            False -> list.append(state.insertion_order, [key])
          }
          Ok(MapState(
            sequenced: dict.insert(state.sequenced, key, acked_value),
            insertion_order: insertion_order,
            pending: pending,
          ))
        }
        Ok(#(_, PendingLifetime(_, []), _))
        | Ok(#(_, PendingDelete(_), _))
        | Ok(#(_, PendingClear, _))
        | Error(Nil) ->
          Error(UnexpectedAck(op, "expected pending lifetime for key " <> key))
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending-queue helpers
// ─────────────────────────────────────────────────────────────────────────────

/// The most recent pending entry that affects `key`. That entry is a lifetime
/// of the key, a delete of the key, or a clear. The TypeScript kernel uses
/// `findLast` with the same predicate.
fn latest_pending_for(
  pending: List(PendingEntry),
  key: String,
) -> Result(PendingEntry, Nil) {
  list.reverse(pending)
  |> list.find(fn(entry) { pending_matches_key(entry, key) })
}

fn pending_matches_key(entry: PendingEntry, key: String) -> Bool {
  case entry {
    PendingClear -> True
    PendingDelete(k) -> k == key
    PendingLifetime(k, _) -> k == key
  }
}

fn has_pending_for(pending: List(PendingEntry), key: String) -> Bool {
  list.any(pending, fn(entry) { pending_matches_key(entry, key) })
}

fn has_pending_delete_or_clear(
  pending: List(PendingEntry),
  key: String,
) -> Bool {
  list.any(pending, fn(entry) {
    case entry {
      PendingClear -> True
      PendingDelete(k) -> k == key
      PendingLifetime(_, _) -> False
    }
  })
}

fn has_pending_entry_for_key(pending: List(PendingEntry), key: String) -> Bool {
  list.any(pending, fn(entry) {
    case entry {
      PendingDelete(k) -> k == key
      PendingLifetime(k, _) -> k == key
      PendingClear -> False
    }
  })
}

fn last_delete_or_clear_index(
  indexed: List(#(Int, PendingEntry)),
  key: String,
) -> Int {
  list.fold(indexed, -1, fn(acc, pair) {
    case pair.1 {
      PendingClear -> pair.0
      PendingDelete(k) if k == key -> pair.0
      PendingDelete(_) -> acc
      PendingLifetime(_, _) -> acc
    }
  })
}

/// Append a set to the most recent pending entry for `key`. The caller must
/// have confirmed that the entry is a lifetime.
fn append_to_latest_lifetime(
  pending: List(PendingEntry),
  key: String,
  value: Json,
) -> List(PendingEntry) {
  list.reverse(pending)
  |> do_append_to_first_lifetime(key, value)
  |> list.reverse
}

fn do_append_to_first_lifetime(
  reversed: List(PendingEntry),
  key: String,
  value: Json,
) -> List(PendingEntry) {
  case reversed {
    [] -> []
    [PendingLifetime(k, sets), ..rest] if k == key -> [
      PendingLifetime(k, list.append(sets, [value])),
      ..rest
    ]
    [entry, ..rest] -> [entry, ..do_append_to_first_lifetime(rest, key, value)]
  }
}

/// Split the pending queue at the first entry for `key` that is not a clear.
/// The TypeScript kernel uses `findIndex` in its local ack handlers.
fn split_at_first_for_key(
  pending: List(PendingEntry),
  key: String,
) -> Result(#(List(PendingEntry), PendingEntry, List(PendingEntry)), Nil) {
  do_split_at_first_for_key(pending, key, [])
}

fn do_split_at_first_for_key(
  pending: List(PendingEntry),
  key: String,
  seen: List(PendingEntry),
) -> Result(#(List(PendingEntry), PendingEntry, List(PendingEntry)), Nil) {
  case pending {
    [] -> Error(Nil)
    [PendingDelete(k) as entry, ..rest] if k == key ->
      Ok(#(list.reverse(seen), entry, rest))
    [PendingLifetime(k, _) as entry, ..rest] if k == key ->
      Ok(#(list.reverse(seen), entry, rest))
    [entry, ..rest] -> do_split_at_first_for_key(rest, key, [entry, ..seen])
  }
}
