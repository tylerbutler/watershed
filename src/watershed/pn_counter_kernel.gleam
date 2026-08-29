//// The first lattice-backed kernel: an integer counter that reconciles with a
//// state-based delta CRDT (`lattice_counters/pn_counter`), and not with
//// arithmetic that this project writes.
////
//// `counter_kernel` adds the op amounts. This kernel merges CRDT deltas.
//// `merge` is commutative, associative, and idempotent. To merge a delta that
//// already applied thus changes nothing, whether that delta comes from a stash
//// replay, a resend, or a duplicate delivery. A summary is the sequenced CRDT
//// state, and a load is `merge(new(my_id), summary)`. There is no special
//// rebase.
////
//// The kernel is identified by replica. Every client must construct it with a
//// unique `ReplicaId`. Without that, concurrent updates max-merge onto one
//// replica key, and the counter loses increments. In every other way the
//// behaviour is the same as `counter_kernel`: optimistic local updates, a FIFO
//// ack, a LIFO rollback, and ack transparency.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id.{type ReplicaId}
import lattice_counters/pn_counter.{type PNCounter}

pub type PnCounterState {
  PnCounterState(
    replica_id: ReplicaId,
    /// The sequenced deltas only, which are the acked local deltas and the
    /// remote deltas. A summary stores this state.
    sequenced: PNCounter,
    /// `sequenced` joined with every pending delta. The kernel caches this
    /// value, so a read is O(1) and so the next local delta computes its
    /// cumulative count from the correct base. `check_cache_coherence` checks
    /// that the cache agrees.
    optimistic: PNCounter,
    /// A FIFO queue of the local ops in flight, oldest first, the same as in
    /// `counter_kernel`.
    pending: List(PendingDelta),
    next_pending_message_id: Int,
  )
}

/// A submitted local op with the local metadata that matches the acks and the
/// rollbacks. The metadata is local only. It is not part of the wire op.
pub type PendingDelta {
  PendingDelta(delta: PNCounter, amount: Int, message_id: Int)
}

/// The wire op: the CRDT delta with the signed intent amount. The delta alone
/// would converge. The op keeps `amount` for the ack and rollback checks, for
/// the event reports, for independence from the oracle, and to make a failure
/// dump readable.
pub type PnCounterOp {
  Update(amount: Int, delta: PNCounter)
}

pub type PnCounterEvent {
  /// `applied` is the observed change of the value. For a remote delta it can
  /// differ from the nominal amount of the op, when the state already
  /// contained part of that delta. The kernel emits no event at all when the
  /// whole merge changed nothing, which occurs for an idempotent duplicate. A
  /// local update always reports its amount, and zero is an amount.
  /// `counter_kernel` behaves the same way.
  Updated(applied: Int, new_value: Int)
}

/// The kernel returns this error when a local ack or rollback does not agree
/// with the pending queue. A runtime caller must treat this error as fatal. It
/// must not continue with divergent state.
pub type KernelError {
  UnexpectedAck(op: PnCounterOp, detail: String)
  UnexpectedRollback(op: PnCounterOp, detail: String)
}

pub fn new(replica_id: ReplicaId) -> PnCounterState {
  let zero = pn_counter.new(replica_id)
  PnCounterState(
    replica_id: replica_id,
    sequenced: zero,
    optimistic: zero,
    pending: [],
    next_pending_message_id: 0,
  )
}

/// An optimistic read: the sequenced state with the pending local deltas.
/// `counter_kernel` behaves the same way.
pub fn value(state: PnCounterState) -> Int {
  pn_counter.value(state.optimistic)
}

/// A committed-only read: the value that a summary would contain now.
pub fn sequenced_value(state: PnCounterState) -> Int {
  pn_counter.value(state.sequenced)
}

/// Apply a signed local update optimistically, and return the outbound op with
/// its local message id. This function handles the sign, so the lattice
/// mutators always receive a magnitude of zero or more.
pub fn update(
  state: PnCounterState,
  amount: Int,
) -> #(PnCounterState, List(PnCounterEvent), PnCounterOp, Int) {
  let #(optimistic, delta) = signed_delta(state.optimistic, amount)
  let message_id = state.next_pending_message_id
  let new_value = pn_counter.value(optimistic)
  #(
    PnCounterState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [
        PendingDelta(delta, amount, message_id),
      ]),
      next_pending_message_id: message_id + 1,
    ),
    [Updated(amount, new_value)],
    Update(amount, delta),
    message_id,
  )
}

/// The ack-free p2p form of `update`. It writes the same delta, but it merges
/// that delta into the confirmed state and the visible state immediately. It
/// queues no pending entry for a later ack. It always reports `amount`, the
/// same as `update`, because this is still a local edit. `counter_kernel`
/// behaves the same way.
pub fn p2p_update(
  state: PnCounterState,
  amount: Int,
) -> #(PnCounterState, List(PnCounterEvent), PnCounterOp) {
  let #(_optimistic, delta) = signed_delta(state.optimistic, amount)
  let sequenced = pn_counter.merge(state.sequenced, delta)
  let optimistic = pn_counter.merge(state.optimistic, delta)
  let new_value = pn_counter.value(optimistic)
  let new_state =
    PnCounterState(..state, sequenced: sequenced, optimistic: optimistic)
  #(new_state, [Updated(amount, new_value)], Update(amount, delta))
}

/// Merge the full confirmed CRDT state of a peer into this state. This is
/// the ack-free equivalent of `apply_remote`. It takes a `state` or
/// `channel` snapshot, not one delta.
///
/// A lattice merge is a join, so it never discards a winner. The result is
/// the least upper bound of the two sides.
pub fn p2p_merge(
  state: PnCounterState,
  other: PNCounter,
) -> #(PnCounterState, List(PnCounterEvent)) {
  let before = pn_counter.value(state.optimistic)
  let optimistic = pn_counter.merge(state.optimistic, other)
  let after = pn_counter.value(optimistic)
  let new_state =
    PnCounterState(
      ..state,
      sequenced: pn_counter.merge(state.sequenced, other),
      optimistic: optimistic,
    )
  case after == before {
    True -> #(new_state, [])
    False -> #(new_state, [Updated(after - before, after)])
  }
}

/// Apply a sequenced op from another client. Merge its delta into the
/// sequenced base and into the optimistic cache. The lattice laws make the
/// order against the pending deltas unimportant: `(s ⊔ d) ⊔ P = (s ⊔ P) ⊔ d`.
/// The kernel emits the observed change of the optimistic value. A merge that
/// changes nothing, because the delta is a duplicate or the state already
/// contains it, emits no event.
pub fn apply_remote(
  state: PnCounterState,
  op: PnCounterOp,
) -> #(PnCounterState, List(PnCounterEvent)) {
  let Update(_, delta) = op
  let before = pn_counter.value(state.optimistic)
  let optimistic = pn_counter.merge(state.optimistic, delta)
  let after = pn_counter.value(optimistic)
  let new_state =
    PnCounterState(
      ..state,
      sequenced: pn_counter.merge(state.sequenced, delta),
      optimistic: optimistic,
    )
  case after == before {
    True -> #(new_state, [])
    False -> #(new_state, [Updated(after - before, after)])
  }
}

/// Retire the oldest pending op when the local op returns sequenced. Merge its
/// delta into `sequenced` only. `optimistic` already contains that delta, so
/// the observed value does not change. This is ack transparency.
pub fn ack_local(
  state: PnCounterState,
  op: PnCounterOp,
) -> Result(PnCounterState, KernelError) {
  do_ack(state, op, None)
}

/// The same as `ack_local`, and it also checks the local op metadata.
pub fn ack_local_with_message_id(
  state: PnCounterState,
  op: PnCounterOp,
  message_id: Int,
) -> Result(PnCounterState, KernelError) {
  do_ack(state, op, Some(message_id))
}

fn do_ack(
  state: PnCounterState,
  op: PnCounterOp,
  expected_message_id: Option(Int),
) -> Result(PnCounterState, KernelError) {
  case state.pending {
    [] -> Error(UnexpectedAck(op, "pending queue is empty"))
    [PendingDelta(delta, amount, pending_message_id), ..rest] -> {
      let Update(op_amount, op_delta) = op
      let message_id_matches = case expected_message_id {
        None -> True
        Some(message_id) -> message_id == pending_message_id
      }
      case op_amount == amount && op_delta == delta && message_id_matches {
        True ->
          Ok(
            PnCounterState(
              ..state,
              sequenced: pn_counter.merge(state.sequenced, delta),
              pending: rest,
            ),
          )
        False ->
          Error(UnexpectedAck(
            op,
            "expected pending update "
              <> int.to_string(amount)
              <> " with message id "
              <> int.to_string(pending_message_id)
              <> ", got update "
              <> int.to_string(op_amount),
          ))
      }
    }
  }
}

/// Roll back the newest pending op. A merge has no inverse, so the kernel
/// computes the optimistic cache again from `sequenced` and the pending deltas
/// that remain. A compensating event reports the amount that the rollback
/// removed.
pub fn rollback(
  state: PnCounterState,
  op: PnCounterOp,
  message_id: Int,
) -> Result(#(PnCounterState, List(PnCounterEvent)), KernelError) {
  case pop_last(state.pending) {
    Error(_) -> Error(UnexpectedRollback(op, "pending queue is empty"))
    Ok(#(PendingDelta(delta, amount, pending_message_id), rest)) -> {
      let Update(op_amount, op_delta) = op
      case
        op_amount == amount
        && op_delta == delta
        && message_id == pending_message_id
      {
        True -> {
          let optimistic =
            list.fold(rest, state.sequenced, fn(acc, pending) {
              pn_counter.merge(acc, pending.delta)
            })
          let new_value = pn_counter.value(optimistic)
          Ok(
            #(PnCounterState(..state, optimistic: optimistic, pending: rest), [
              Updated(0 - amount, new_value),
            ]),
          )
        }
        False ->
          Error(UnexpectedRollback(
            op,
            "expected newest pending update "
              <> int.to_string(amount)
              <> " with message id "
              <> int.to_string(pending_message_id)
              <> ", got update "
              <> int.to_string(op_amount)
              <> " with message id "
              <> int.to_string(message_id),
          ))
      }
    }
  }
}

/// Apply a stashed op again after a reconnect, so that it is visible
/// optimistically and is pending again. The function returns the *same* op,
/// for routing.
///
/// The re-increment path of `counter_kernel` differs. This function merges the
/// cumulative delta of the op. That merge is idempotent when the delta already
/// applied, for example when the summary that the client loaded already
/// contained it. That property is the CRDT benefit that this kernel proves.
/// The kernel emits the observed change of the value, and it emits nothing
/// when the merge changed nothing.
pub fn apply_stashed_op(
  state: PnCounterState,
  op: PnCounterOp,
) -> #(PnCounterState, List(PnCounterEvent), PnCounterOp, Int) {
  let Update(amount, delta) = op
  let before = pn_counter.value(state.optimistic)
  let optimistic = pn_counter.merge(state.optimistic, delta)
  let after = pn_counter.value(optimistic)
  let message_id = state.next_pending_message_id
  let new_state =
    PnCounterState(
      ..state,
      optimistic: optimistic,
      pending: list.append(state.pending, [
        PendingDelta(delta, amount, message_id),
      ]),
      next_pending_message_id: message_id + 1,
    )
  let events = case after == before {
    True -> []
    False -> [Updated(after - before, after)]
  }
  #(new_state, events, op, message_id)
}

/// The summary to store: the sequenced CRDT state only. It contains no pending
/// local delta, the same as `sequenced_entries` of the map kernel.
pub fn summary(state: PnCounterState) -> Json {
  pn_counter.to_json(state.sequenced)
}

/// Build a new state from a stored summary. The parsed counter carries the
/// replica identity of the client that wrote the summary. The function thus
/// re-brands it with `merge(new(replica_id), parsed)`, because the lattice
/// merge keeps the self id of `a`. Without that step, the loading client would
/// submit its future deltas under the replica key of the summary writer, and
/// the two would collide.
pub fn from_summary(
  summary_json: String,
  replica_id: ReplicaId,
) -> Result(PnCounterState, json.DecodeError) {
  case pn_counter.from_json(summary_json) {
    Error(error) -> Error(error)
    Ok(parsed) -> {
      let sequenced = pn_counter.merge(pn_counter.new(replica_id), parsed)
      Ok(PnCounterState(
        replica_id: replica_id,
        sequenced: sequenced,
        optimistic: sequenced,
        pending: [],
        next_pending_message_id: 0,
      ))
    }
  }
}

/// Build a new state from a sequenced CRDT value that is already parsed. That
/// value is the snapshot payload of the channel layer. The function re-brands
/// it under the `replica_id` of the loading client with
/// `merge(new(replica_id), state)`, the same as `from_summary`, so that the
/// future deltas use the correct replica key.
pub fn from_sequenced(
  state: PNCounter,
  replica_id: ReplicaId,
) -> PnCounterState {
  let sequenced = pn_counter.merge(pn_counter.new(replica_id), state)
  PnCounterState(
    replica_id: replica_id,
    sequenced: sequenced,
    optimistic: sequenced,
    pending: [],
    next_pending_message_id: 0,
  )
}

/// The state and the sparse delta for one signed local update. The function
/// splits the sign here, so the grow-only halves of the counter each receive a
/// magnitude of zero or more.
fn signed_delta(counter: PNCounter, amount: Int) -> #(PNCounter, PNCounter) {
  case amount >= 0 {
    True -> pn_counter.increment_with_delta(counter, amount)
    False -> pn_counter.decrement_with_delta(counter, 0 - amount)
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

/// An invariant for the tests: the cached `optimistic` state must equal
/// `sequenced` with every pending delta merged into it again. This function is
/// the `check` hook of the fuzz model, so a test finds a stale cache one
/// command after the fault.
pub fn check_cache_coherence(state: PnCounterState) -> Result(Nil, String) {
  let recomputed =
    list.fold(state.pending, state.sequenced, fn(acc, pending) {
      pn_counter.merge(acc, pending.delta)
    })
  case recomputed == state.optimistic {
    True -> Ok(Nil)
    False ->
      Error(
        "optimistic cache diverged from sequenced + pending: cached value "
        <> int.to_string(pn_counter.value(state.optimistic))
        <> ", recomputed "
        <> int.to_string(pn_counter.value(recomputed)),
      )
  }
}
