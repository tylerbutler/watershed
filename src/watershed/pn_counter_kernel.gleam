//// The first lattice-backed kernel: an int counter whose reconciliation is
//// a state-based delta CRDT (`lattice_counters/pn_counter`) instead of
//// hand-rolled arithmetic.
////
//// Where `counter_kernel` adds op amounts, this kernel merges CRDT deltas:
//// `merge` is commutative, associative, and idempotent, so re-merging a
//// delta that already applied (stash replay, resend, duplicate delivery)
//// is a no-op by construction, and a summary is just the sequenced CRDT
//// state — loading is `merge(new(my_id), summary)`, no bespoke rebase.
////
//// The kernel is replica-identified: every client must construct it with a
//// unique `ReplicaId`, or concurrent updates max-merge onto one replica key
//// and lose increments. Behavioral parity with `counter_kernel` otherwise:
//// optimistic local updates, FIFO ack, LIFO rollback, ack transparency.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id.{type ReplicaId}
import lattice_counters/pn_counter.{type PNCounter}

pub type PnCounterState {
  PnCounterState(
    replica_id: ReplicaId,
    /// Only sequenced (acked local + remote) deltas merged in. This is what
    /// summaries persist.
    sequenced: PNCounter,
    /// `sequenced` ⊔ all pending deltas — cached so reads are O(1) and so
    /// the next local delta's cumulative count is computed off the right
    /// base. `check_cache_coherence` validates the redundancy.
    optimistic: PNCounter,
    /// FIFO queue of in-flight local ops (oldest first), counter-style.
    pending: List(PendingDelta),
    next_pending_message_id: Int,
  )
}

/// A submitted local op plus the local metadata used to match acks and
/// rollbacks. Local-only; not part of the wire op.
pub type PendingDelta {
  PendingDelta(delta: PNCounter, amount: Int, message_id: Int)
}

/// The wire op: the CRDT delta plus the signed intent amount. The delta
/// alone would converge, but `amount` is kept for ack/rollback validation,
/// event reporting, oracle independence, and failure-dump readability.
pub type PnCounterOp {
  Update(amount: Int, delta: PNCounter)
}

pub type PnCounterEvent {
  /// `applied` is the actual observed value change — for a remote delta it
  /// may differ from the op's nominal amount when part of the delta was
  /// already subsumed, and no event fires at all when the whole merge was a
  /// no-op (idempotent duplicate). Local updates always report their amount,
  /// including zero (counter parity).
  Updated(applied: Int, new_value: Int)
}

/// Returned when a local ack or rollback does not line up with the pending
/// queue. Runtime callers should treat this as fatal rather than continue
/// with divergent state.
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

/// Optimistic read (counter parity): sequenced plus pending local deltas.
pub fn value(state: PnCounterState) -> Int {
  pn_counter.value(state.optimistic)
}

/// Committed-only read: what a summary taken now would contain.
pub fn sequenced_value(state: PnCounterState) -> Int {
  pn_counter.value(state.sequenced)
}

/// Optimistically apply a signed local update and return the outbound op
/// plus its local message id. Sign is routed here so only the non-panicking
/// `try_*` lattice mutators are ever reachable, always with a non-negative
/// magnitude.
pub fn update(
  state: PnCounterState,
  amount: Int,
) -> #(PnCounterState, List(PnCounterEvent), PnCounterOp, Int) {
  // The magnitude is non-negative by construction, so the NegativeDelta
  // error arm is unreachable.
  let assert Ok(#(optimistic, delta)) = case amount >= 0 {
    True -> pn_counter.try_increment_with_delta(state.optimistic, amount)
    False -> pn_counter.try_decrement_with_delta(state.optimistic, 0 - amount)
  }
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

/// Apply a sequenced op from another client: merge its delta into both the
/// sequenced base and the optimistic cache (lattice laws make the order
/// against pending deltas irrelevant: `(s ⊔ d) ⊔ P = (s ⊔ P) ⊔ d`). Emits
/// the observed optimistic-value diff; a no-op merge (duplicate or subsumed
/// delta) emits nothing.
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

/// Retire the oldest pending op when our local op comes back sequenced,
/// merging its delta into `sequenced` only — `optimistic` already contains
/// it, so the observed value does not change (ack transparency).
pub fn ack_local(
  state: PnCounterState,
  op: PnCounterOp,
) -> Result(PnCounterState, KernelError) {
  do_ack(state, op, None)
}

/// Same as `ack_local`, additionally validating the local op metadata.
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

/// Roll back the newest pending op. Merge is not invertible, so the
/// optimistic cache is recomputed from `sequenced` plus the remaining
/// pending deltas; a compensating event reports the undone amount.
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

/// Re-apply a stashed op after reconnect so it is optimistically visible
/// and pending again, returning the SAME op for routing. Unlike counter's
/// re-increment path, this merges the op's cumulative delta — idempotent
/// when the delta already applied (e.g. it was sequenced into the summary
/// the client reloaded from), which is the CRDT payoff this kernel exists
/// to prove. Emits the observed value diff; nothing when the merge was a
/// no-op.
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

/// The persistable summary: the sequenced CRDT state only — pending local
/// deltas are excluded, exactly like map's `sequenced_entries`.
pub fn summary(state: PnCounterState) -> Json {
  pn_counter.to_json(state.sequenced)
}

/// Build a clean state from a stored summary. The parsed counter carries
/// the *summarizer's* replica identity, so it is re-branded via
/// `merge(new(replica_id), parsed)` — lattice's merge keeps `a`'s self id —
/// or the loading client would submit future deltas under the summarizer's
/// replica key and collide.
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

/// Test-facing invariant: the cached `optimistic` state must equal
/// `sequenced` with every pending delta re-merged. Wired as the fuzz
/// model's `check` hook so a stale cache is caught one command after the
/// fault.
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
