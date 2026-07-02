//// Pure port of FluidFramework's `packages/dds/map/src/mapKernel.ts`.
////
//// No process, no side effects: every operation returns the new state plus
//// the events and outbound op it produced. The runtime actor owns
//// sequencing concerns (CSN/RSN, ack matching by `(client_id, csn)`); the
//// kernel only assumes acks arrive in submission order (FIFO), mirroring the
//// TS kernel's reference-identity asserts.
////
//// State is split the same way as the TS kernel:
//// - `sequenced`: values confirmed by the server (plus `insertion_order`,
////   since Gleam's `Dict` is unordered but the TS kernel relies on JS `Map`
////   insertion-order iteration)
//// - `pending`: optimistic local changes not yet acked, with consecutive
////   sets to a key aggregated into "lifetimes" so iteration order stays
////   correct across remote ops

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
  /// One or more consecutive local sets to a key, oldest first. A delete or
  /// clear terminates the lifetime; a later set starts a new one.
  PendingLifetime(key: String, sets: List(Json))
  PendingDelete(key: String)
  PendingClear
}

/// A map operation as it travels over the wire (before envelope/encoding,
/// which belong to the wire layer).
pub type MapOp {
  Set(key: String, value: Json)
  Delete(key: String)
  Clear
}

pub type MapEvent {
  ValueChanged(key: String, previous_value: Option(Json), local: Bool)
  Cleared(local: Bool)
}

/// Returned when an ack does not line up with the pending queue. The TS
/// kernel assert-fails here; callers (the runtime actor) should treat this
/// as fatal and crash rather than continue with divergent state.
pub type KernelError {
  UnexpectedAck(op: MapOp, detail: String)
}

pub fn new() -> MapState {
  MapState(sequenced: dict.new(), insertion_order: [], pending: [])
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

/// Optimistic read: sequenced data overlaid with pending local changes.
pub fn get(state: MapState, key: String) -> Option(Json) {
  case latest_pending_for(state.pending, key) {
    None -> dict.get(state.sequenced, key) |> option.from_result
    Some(PendingLifetime(_, sets)) -> list.last(sets) |> option.from_result
    Some(PendingDelete(_)) | Some(PendingClear) -> None
  }
}

pub fn has(state: MapState, key: String) -> Bool {
  get(state, key) != None
}

pub fn size(state: MapState) -> Int {
  list.length(entries(state))
}

pub fn keys(state: MapState) -> List(String) {
  entries(state) |> list.map(fn(entry) { entry.0 })
}

/// Optimistically observable entries, in the TS iterator's order: sequenced
/// keys first (insertion order, skipping keys with a pending delete/clear),
/// then pending lifetimes that survive any later delete/clear.
pub fn entries(state: MapState) -> List(#(String, Json)) {
  let sequenced_phase =
    list.filter_map(state.insertion_order, fn(key) {
      // A pending delete/clear means this key either disappears or re-appears
      // later at its lifetime's position, not here.
      case has_pending_delete_or_clear(state.pending, key) {
        True -> Error(Nil)
        False ->
          case get(state, key) {
            Some(value) -> Ok(#(key, value))
            None -> Error(Nil)
          }
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
        _ -> Error(Nil)
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
    Some(PendingLifetime(_, _)) ->
      append_to_latest_lifetime(state.pending, key, value)
    _ -> list.append(state.pending, [PendingLifetime(key, [value])])
  }
  #(
    MapState(..state, pending: pending),
    [ValueChanged(key, previous, True)],
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
    Some(value) -> [ValueChanged(key, Some(value), True)]
    None -> []
  }
  #(MapState(..state, pending: pending), events, Delete(key))
}

pub fn clear(state: MapState) -> #(MapState, List(MapEvent), MapOp) {
  let visible = entries(state)
  let pending = list.append(state.pending, [PendingClear])
  let events = [
    Cleared(True),
    ..list.map(visible, fn(entry) { ValueChanged(entry.0, Some(entry.1), True) })
  ]
  #(MapState(..state, pending: pending), events, Clear)
}

// ─────────────────────────────────────────────────────────────────────────────
// Remote operations
// ─────────────────────────────────────────────────────────────────────────────

/// Apply a sequenced op from another client. Events are suppressed when
/// pending local changes mask the remote change optimistically.
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
        False -> [ValueChanged(key, previous, False)]
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
        False -> [ValueChanged(key, previous, False)]
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
            ValueChanged(entry.0, Some(entry.1), False)
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

/// Commit an acked local op: pending → sequenced. Acks must arrive in
/// submission order; a mismatch means the runtime routed an ack we never
/// submitted (or out of order) and is fatal.
///
/// Acking never emits events — the optimistic view already reflected the op
/// when it was submitted.
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
        _ -> Error(UnexpectedAck(op, "expected pending delete for key " <> key))
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
        _ ->
          Error(UnexpectedAck(op, "expected pending lifetime for key " <> key))
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending-queue helpers
// ─────────────────────────────────────────────────────────────────────────────

/// The most recent pending entry that affects `key`: a lifetime or delete of
/// that key, or any clear (TS `findLast` with the same predicate).
fn latest_pending_for(
  pending: List(PendingEntry),
  key: String,
) -> Option(PendingEntry) {
  list.reverse(pending)
  |> list.find(fn(entry) { pending_matches_key(entry, key) })
  |> option.from_result
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
      _ -> acc
    }
  })
}

/// Append a set to the latest pending entry matching `key`, which the caller
/// has established is a lifetime.
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

/// Split the pending queue at the first non-clear entry for `key` (TS
/// `findIndex` in the local ack handlers).
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
