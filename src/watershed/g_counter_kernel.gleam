//// A grow-only counter channel kernel, backed by the state-based delta CRDT
//// `lattice_counters/g_counter`.
////
//// The kernel keeps the same lifecycle as `pn_counter_kernel`: optimistic
//// local edits, a FIFO acknowledgment, a LIFO rollback, and acknowledgment
//// transparency. It merges CRDT fragments. It does not add amounts. A merge
//// is commutative, associative, and idempotent, thus a fragment that applied
//// already changes nothing. That property holds for a duplicate delivery, a
//// resend, and a stash replay.
////
//// The counter is grow-only. The public API has no decrement function, and a
//// negative amount is rejected before the state changes. Confirmed state can
//// only increase. Optimistic state can decrease, because a rollback removes a
//// local edit that the server did not sequence.
////
//// The kernel is identified by replica. Every client must construct it with a
//// unique `ReplicaId`. Without that, concurrent increments merge onto one
//// replica key with a maximum, and the counter loses increments.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id.{type ReplicaId}
import lattice_counters/g_counter.{type GCounter}

pub type GCounterState {
  GCounterState(
    replica_id: ReplicaId,
    /// The sequenced fragments only, which are the acknowledged local
    /// fragments and the remote fragments. A summary stores this state.
    sequenced: GCounter,
    /// `sequenced` joined with every pending fragment. The kernel caches this
    /// value, so a read is O(1) and so the next local fragment computes its
    /// cumulative count from the correct base. `check_cache_coherence` checks
    /// that the cache agrees.
    optimistic: GCounter,
    /// A FIFO queue of the local operations in flight, oldest first.
    pending: List(PendingDelta),
    next_pending_message_id: Int,
  )
}

/// A submitted local operation with the local metadata that matches the
/// acknowledgments and the rollbacks. The metadata is local only. It is not
/// part of the wire operation.
pub type PendingDelta {
  PendingDelta(delta: GCounter, amount: Int, message_id: Int)
}

/// The wire operation: the CRDT fragment with the intent amount. The fragment
/// alone would converge. The operation keeps `amount` for the acknowledgment
/// and rollback checks, for the event reports, and to make a failure dump
/// readable.
pub type GCounterOperation {
  Increment(amount: Int, delta: GCounter)
}

pub type GCounterEvent {
  /// `applied` is the observed change of the value. For a remote fragment it
  /// can differ from the nominal amount of the operation, when the state
  /// contained part of that fragment already. The kernel emits no event when
  /// the merge changed nothing, which occurs for an idempotent duplicate and
  /// for an increment of zero.
  Updated(applied: Int, new_value: Int)
}

/// The kernel returns this error when a caller asks for an edit that the
/// grow-only contract does not permit. The state does not change, and no
/// operation goes out.
pub type EditError {
  NegativeIncrement(amount: Int)
}

/// A short description of an edit error, for a caller that reports text.
pub fn edit_error_text(error: EditError) -> String {
  case error {
    NegativeIncrement(amount) ->
      "a grow-only counter does not accept the negative amount "
      <> int.to_string(amount)
  }
}

/// The kernel returns this error when a local acknowledgment or rollback does
/// not agree with the pending queue. A runtime caller must treat this error as
/// fatal. It must not continue with divergent state.
pub type KernelError {
  UnexpectedAck(operation: GCounterOperation, detail: String)
  UnexpectedRollback(operation: GCounterOperation, detail: String)
}

pub fn new(replica_id: ReplicaId) -> GCounterState {
  let zero = g_counter.new(replica_id)
  GCounterState(
    replica_id: replica_id,
    sequenced: zero,
    optimistic: zero,
    pending: [],
    next_pending_message_id: 0,
  )
}

/// An optimistic read: the sequenced state with the pending local fragments.
pub fn value(state: GCounterState) -> Int {
  g_counter.value(state.optimistic)
}

/// A committed-only read: the value that a summary would contain now.
pub fn sequenced_value(state: GCounterState) -> Int {
  g_counter.value(state.sequenced)
}

/// Apply a local increment optimistically, and return the outbound operation
/// with its local message id. A negative amount is an error, and the state
/// does not change. Zero is valid, and it emits no event.
pub fn increment(
  state: GCounterState,
  amount: Int,
) -> Result(
  #(GCounterState, List(GCounterEvent), GCounterOperation, Int),
  EditError,
) {
  case g_counter.increment_with_delta(state.optimistic, amount) {
    Error(g_counter.NegativeDelta(delta)) -> Error(NegativeIncrement(delta))
    Ok(#(optimistic, delta)) -> {
      let before = g_counter.value(state.optimistic)
      let after = g_counter.value(optimistic)
      let message_id = state.next_pending_message_id
      Ok(#(
        GCounterState(
          ..state,
          optimistic: optimistic,
          pending: list.append(state.pending, [
            PendingDelta(delta, amount, message_id),
          ]),
          next_pending_message_id: message_id + 1,
        ),
        change_events(before, after),
        Increment(amount, delta),
        message_id,
      ))
    }
  }
}

/// The acknowledgment-free p2p form of `increment`. It writes the same
/// fragment, but it merges that fragment into the confirmed state and the
/// visible state immediately. It queues no pending entry for a later
/// acknowledgment.
pub fn p2p_increment(
  state: GCounterState,
  amount: Int,
) -> Result(#(GCounterState, List(GCounterEvent), GCounterOperation), EditError) {
  case g_counter.increment_with_delta(state.optimistic, amount) {
    Error(g_counter.NegativeDelta(delta)) -> Error(NegativeIncrement(delta))
    Ok(#(_optimistic, delta)) -> {
      let before = g_counter.value(state.optimistic)
      let optimistic = g_counter.merge(state.optimistic, delta)
      let after = g_counter.value(optimistic)
      Ok(#(
        GCounterState(
          ..state,
          sequenced: g_counter.merge(state.sequenced, delta),
          optimistic: optimistic,
        ),
        change_events(before, after),
        Increment(amount, delta),
      ))
    }
  }
}

/// Merge the full confirmed CRDT state of a peer into this state. This is the
/// acknowledgment-free equivalent of `apply_remote`. It takes a `state` or
/// `channel` snapshot, not one fragment.
///
/// A lattice merge is a join, so it never discards a winner. The result is the
/// least upper bound of the two sides.
pub fn p2p_merge(
  state: GCounterState,
  other: GCounter,
) -> #(GCounterState, List(GCounterEvent)) {
  let before = g_counter.value(state.optimistic)
  let optimistic = g_counter.merge(state.optimistic, other)
  let after = g_counter.value(optimistic)
  #(
    GCounterState(
      ..state,
      sequenced: g_counter.merge(state.sequenced, other),
      optimistic: optimistic,
    ),
    change_events(before, after),
  )
}

/// Apply a sequenced operation from another client. Merge its fragment into
/// the sequenced base and into the optimistic cache. The lattice laws make the
/// order against the pending fragments unimportant: `(s ⊔ d) ⊔ P = (s ⊔ P) ⊔ d`.
/// A merge that changes nothing emits no event.
pub fn apply_remote(
  state: GCounterState,
  operation: GCounterOperation,
) -> #(GCounterState, List(GCounterEvent)) {
  let Increment(_, delta) = operation
  p2p_merge(state, delta)
}

/// Retire the oldest pending operation when the local operation returns
/// sequenced. Merge its fragment into `sequenced` only. `optimistic` contains
/// that fragment already, so the observed value does not change. This is
/// acknowledgment transparency.
pub fn ack_local(
  state: GCounterState,
  operation: GCounterOperation,
) -> Result(GCounterState, KernelError) {
  do_ack(state, operation, None)
}

/// The same as `ack_local`, and it also checks the local operation metadata.
pub fn ack_local_with_message_id(
  state: GCounterState,
  operation: GCounterOperation,
  message_id: Int,
) -> Result(GCounterState, KernelError) {
  do_ack(state, operation, Some(message_id))
}

fn do_ack(
  state: GCounterState,
  operation: GCounterOperation,
  expected_message_id: Option(Int),
) -> Result(GCounterState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck(operation, "pending queue is empty"))
    [PendingDelta(delta, amount, pending_message_id), ..rest] -> {
      let Increment(operation_amount, operation_delta) = operation
      let message_id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case
        operation_amount == amount
        && operation_delta == delta
        && message_id_matches
      {
        True ->
          Ok(
            GCounterState(
              ..state,
              sequenced: g_counter.merge(state.sequenced, delta),
              pending: rest,
            ),
          )
        False ->
          Error(UnexpectedAck(
            operation,
            "expected pending increment "
              <> int.to_string(amount)
              <> " with message id "
              <> int.to_string(pending_message_id)
              <> ", got increment "
              <> int.to_string(operation_amount),
          ))
      }
    }
  }
}

/// Roll back the newest pending operation. A merge has no inverse, so the
/// kernel computes the optimistic cache again from `sequenced` and the pending
/// fragments that remain. A compensating event reports the amount that the
/// rollback removed. Confirmed state does not change, thus it stays grow-only.
pub fn rollback(
  state: GCounterState,
  operation: GCounterOperation,
  message_id: Int,
) -> Result(#(GCounterState, List(GCounterEvent)), KernelError) {
  case pop_last(state.pending) {
    Error(_) -> Error(UnexpectedRollback(operation, "pending queue is empty"))
    Ok(#(PendingDelta(delta, amount, pending_message_id), rest)) -> {
      let Increment(operation_amount, operation_delta) = operation
      case
        operation_amount == amount
        && operation_delta == delta
        && message_id == pending_message_id
      {
        True -> {
          let before = g_counter.value(state.optimistic)
          let optimistic = rebuild_optimistic(state.sequenced, rest)
          let after = g_counter.value(optimistic)
          Ok(#(
            GCounterState(..state, optimistic: optimistic, pending: rest),
            change_events(before, after),
          ))
        }
        False ->
          Error(UnexpectedRollback(
            operation,
            "expected newest pending increment "
              <> int.to_string(amount)
              <> " with message id "
              <> int.to_string(pending_message_id)
              <> ", got increment "
              <> int.to_string(operation_amount)
              <> " with message id "
              <> int.to_string(message_id),
          ))
      }
    }
  }
}

/// Apply a stashed operation again after a reconnect, so that it is visible
/// optimistically and is pending again. The function returns the *same*
/// operation, for routing. It does not generate another increment.
///
/// The kernel merges the cumulative fragment of the operation. That merge is
/// idempotent when the fragment applied already, for example when the summary
/// that the client loaded contained it. The kernel emits the observed change
/// of the value, and it emits nothing when the merge changed nothing.
pub fn apply_stashed_operation(
  state: GCounterState,
  operation: GCounterOperation,
) -> #(GCounterState, List(GCounterEvent), GCounterOperation, Int) {
  let Increment(amount, delta) = operation
  let before = g_counter.value(state.optimistic)
  let optimistic = g_counter.merge(state.optimistic, delta)
  let after = g_counter.value(optimistic)
  let message_id = state.next_pending_message_id
  #(
    GCounterState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [
        PendingDelta(delta, amount, message_id),
      ]),
      next_pending_message_id: message_id + 1,
    ),
    change_events(before, after),
    operation,
    message_id,
  )
}

/// The summary to store: the sequenced CRDT state only. It contains no pending
/// local fragment.
pub fn summary(state: GCounterState) -> Json {
  g_counter.to_json(state.sequenced)
}

/// Build a new state from a stored summary. The parsed counter carries the
/// replica identity of the client that wrote the summary. The function thus
/// re-brands it with `merge(new(replica_id), parsed)`, because the lattice
/// merge keeps the self id of `a`. Without that step, the loading client would
/// submit its future fragments under the replica key of the summary writer,
/// and the two would collide.
pub fn from_summary(
  summary_json: String,
  replica_id: ReplicaId,
) -> Result(GCounterState, json.DecodeError) {
  case g_counter.from_json(summary_json) {
    Error(error) -> Error(error)
    Ok(parsed) -> Ok(from_sequenced(parsed, replica_id))
  }
}

/// Build a new state from a sequenced CRDT value that is parsed already. That
/// value is the snapshot payload of the channel layer. The function re-brands
/// it under the `replica_id` of the loading client, the same as
/// `from_summary`, so that the future fragments use the correct replica key.
pub fn from_sequenced(state: GCounter, replica_id: ReplicaId) -> GCounterState {
  let sequenced = g_counter.merge(g_counter.new(replica_id), state)
  GCounterState(
    replica_id: replica_id,
    sequenced: sequenced,
    optimistic: sequenced,
    pending: [],
    next_pending_message_id: 0,
  )
}

/// An invariant for the tests: the cached `optimistic` state must equal
/// `sequenced` with every pending fragment merged into it again. This function
/// is the `check` hook of the fuzz model, so a test finds a stale cache one
/// command after the fault.
pub fn check_cache_coherence(state: GCounterState) -> Result(Nil, String) {
  let recomputed = rebuild_optimistic(state.sequenced, state.pending)
  case recomputed == state.optimistic {
    True -> Ok(Nil)
    False ->
      Error(
        "optimistic cache diverged from sequenced + pending: cached value "
        <> int.to_string(g_counter.value(state.optimistic))
        <> ", recomputed "
        <> int.to_string(g_counter.value(recomputed)),
      )
  }
}

fn rebuild_optimistic(
  sequenced: GCounter,
  pending: List(PendingDelta),
) -> GCounter {
  list.fold(pending, sequenced, fn(acc, entry) {
    g_counter.merge(acc, entry.delta)
  })
}

fn change_events(before: Int, after: Int) -> List(GCounterEvent) {
  case after == before {
    True -> []
    False -> [Updated(after - before, after)]
  }
}

fn pop_last(
  pending: List(PendingDelta),
) -> Result(#(PendingDelta, List(PendingDelta)), Nil) {
  case pending {
    [] -> Error(Nil)
    [only] -> Ok(#(only, []))
    [head, ..rest] ->
      case pop_last(rest) {
        Error(_) -> Error(Nil)
        Ok(#(last, init)) -> Ok(#(last, [head, ..init]))
      }
  }
}
