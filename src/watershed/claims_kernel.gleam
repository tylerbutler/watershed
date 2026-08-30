//// Pure port of FluidFramework's `packages/dds/claims/src/claims.ts`.
////
//// Claims is a first-writer-wins key-value DDS, with a compare-and-set on the
//// sequence number of each key. Two properties separate it from the counter
//// kernel and the map kernel, and both properties make it simpler:
////
//// 1. **A read is not optimistic.** `get` and `has` return the committed state
////    only. A pending local claim is not visible until it wins. There is no
////    pending overlay and no rebase machinery, which is the opposite of
////    `map_kernel`.
//// 2. **The sequencing decides acceptance, in the same way for a local
////    operation and a remote operation** (`apply_sequenced`). The kernel
////    accepts the operation when the key is unclaimed, or when the `ref_seq`
////    of the operation equals the sequence number of the committed entry
////    exactly. Every client applies the same rule to the same committed state,
////    so the replicas converge by construction. The local path does one more
////    thing only: it resolves the pending outcome for the caller.
////
//// The new pattern here is the **deferred outcome**. The result of a local
//// claim, which is whether that claim won, is unknowable until the operation
//// returns from the server. The TypeScript class returns a `Promise`. This
//// pure kernel returns a `ClaimOutcome` value from `ack_local`, `rollback`,
//// and `abort_all`, and the runtime owns the asynchronous surface.
//// `last_seen_seq` is a parameter, and not kernel state. The runtime actor
//// owns the sequencing work, the same as for the map kernel, and it already
//// tracks the last sequence number of the container.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub type ClaimsState {
  ClaimsState(
    /// The committed claims: a value with the sequence number of the operation
    /// that set it.
    claims: Dict(String, ClaimEntry),
    /// The pending local claims, keyed by claim key, with one claim for each
    /// key at most. The value is the submitted value. The kernel needs it to
    /// build the `Accepted` outcome, and the handle scan needs it. There is no
    /// queue, because the sequenced operation decides the acceptance, and not
    /// the position in a pending queue.
    pending: Dict(String, Json),
  )
}

pub type ClaimEntry {
  ClaimEntry(value: Json, sequence_number: Int)
}

/// The one claim operation, in its wire form. The write-once path
/// (`claim_once`) and the compare-and-set path (`compare_and_set_claim`) both
/// use this shape.
pub type ClaimOperation {
  Claim(key: String, value: Json, ref_seq: Int)
}

pub type ClaimEvent {
  /// The kernel emits this event when it accepts a sequenced operation. `local`
  /// follows the watershed convention. The map events and the counter events
  /// carry that field, and the TypeScript event does not.
  Claimed(key: String, local: Bool)
}

/// The synchronous result of `claim_once` or `compare_and_set_claim`.
pub type SubmitResult {
  /// The caller must send the operation. Its outcome arrives later, from
  /// `ack_local`. This is the "Pending" status in TypeScript.
  Submitted(state: ClaimsState, operation: ClaimOperation)
  /// `claim_once` found a committed entry, so the caller sends nothing.
  /// This value carries the committed value, which can be a JSON null.
  AlreadyClaimed(current_value: Json)
}

/// The resolved outcome of a pending claim. The kernel returns it after the
/// operation sequences, or after a rollback or an abort. The runtime then
/// delivers it to the caller that waits. It replaces the promise of the
/// TypeScript code.
pub type ClaimOutcome {
  Accepted(value: Json)
  /// The claim lost the race. This value carries the current committed value.
  /// It is `None` only if the key is truly unclaimed, which is the
  /// `T | undefined` type in TypeScript. In practice a loss means that another
  /// claim won, so the value is `Some`. The `Option` type follows the upstream
  /// type. It does not represent a state that this kernel can reach on its
  /// own.
  Lost(current_value: Option(Json))
  Aborted
}

pub type KernelError {
  /// A usage error on the submit side. This is the `UsageError` of the
  /// TypeScript code, as data.
  AlreadyPendingLocally(key: String)
  /// A local ack arrived, and no pending entry matches it. The TypeScript code
  /// accepts that condition quietly. This kernel is strict, the same as the
  /// counter kernel and the map kernel: a routing mismatch is fatal
  /// divergence.
  UnexpectedAck(operation: ClaimOperation, detail: String)
  UnexpectedRollback(operation: ClaimOperation, detail: String)
}

pub fn new() -> ClaimsState {
  ClaimsState(claims: dict.new(), pending: dict.new())
}

/// Build a state that contains committed data only, from the stored summary
/// triples `(key, value, sequence_number)`. The summary keeps the sequence
/// numbers, so the `ref_seq` comparison of a compare-and-set continues to work
/// after a load. A state that you load has no pending entry.
pub fn from_summary(entries: List(#(String, Json, Int))) -> ClaimsState {
  let claims =
    list.fold(entries, dict.new(), fn(acc, entry) {
      let #(key, value, seq) = entry
      dict.insert(acc, key, ClaimEntry(value, seq))
    })
  ClaimsState(claims: claims, pending: dict.new())
}

/// The committed claims to store in a summary, as `(key, value,
/// sequence_number)` triples. The function sorts them by key, so a snapshot is
/// stable.
pub fn summary_entries(state: ClaimsState) -> List(#(String, Json, Int)) {
  dict.to_list(state.claims)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(entry) {
    let #(key, ClaimEntry(value, seq)) = entry
    #(key, value, seq)
  })
}

/// The committed value for a key. The read gives committed data only, by
/// design: a pending local claim is not visible until it wins. The result is
/// `Error(Nil)` when the key is unclaimed.
pub fn get(state: ClaimsState, key: String) -> Result(Json, Nil) {
  case dict.get(state.claims, key) {
    Ok(ClaimEntry(value, _)) -> Ok(value)
    Error(Nil) -> Error(Nil)
  }
}

/// Whether a committed claim exists for a key. This function separates a key
/// that no client set from a key that a client set to a JSON null. It reads
/// committed data only, the same as `get`.
pub fn has(state: ClaimsState, key: String) -> Bool {
  dict.has_key(state.claims, key)
}

/// The write-once submit. If a committed entry exists, the function returns
/// `AlreadyClaimed` at once and sends no operation. If none exists, the
/// function behaves as a compare-and-set against the unclaimed key, and it
/// records `ref_seq = last_seen_seq`.
///
/// The check of the committed state runs *before* the pending guard. A
/// write-once claim on a committed key thus returns `AlreadyClaimed`, also
/// when a compare-and-set for that key is pending locally.
pub fn claim_once(
  state: ClaimsState,
  key: String,
  value: Json,
  last_seen_seq: Int,
) -> Result(SubmitResult, KernelError) {
  case dict.get(state.claims, key) {
    Ok(ClaimEntry(current, _)) -> Ok(AlreadyClaimed(current))
    Error(_) -> submit_claim(state, key, value, last_seen_seq)
  }
}

/// The compare-and-set submit. If the key is claimed, the function records
/// `ref_seq` from the sequence number of the committed entry. If the key is
/// unclaimed, it records `last_seen_seq`. The function always submits, and it
/// never returns `AlreadyClaimed` at once. The sequencing of the operation
/// decides the acceptance.
pub fn compare_and_set_claim(
  state: ClaimsState,
  key: String,
  value: Json,
  last_seen_seq: Int,
) -> Result(SubmitResult, KernelError) {
  let ref_seq = case dict.get(state.claims, key) {
    Ok(ClaimEntry(_, seq)) -> seq
    Error(_) -> last_seen_seq
  }
  submit_claim(state, key, value, ref_seq)
}

fn submit_claim(
  state: ClaimsState,
  key: String,
  value: Json,
  ref_seq: Int,
) -> Result(SubmitResult, KernelError) {
  case dict.has_key(state.pending, key) {
    True -> Error(AlreadyPendingLocally(key))
    False -> {
      let state =
        ClaimsState(..state, pending: dict.insert(state.pending, key, value))
      Ok(Submitted(state, Claim(key, value, ref_seq)))
    }
  }
}

/// The detached apply path. No other client exists, so the function applies
/// the claim directly with the sequence number 0. The runtime decides when a
/// channel is detached, the same as for the map kernel. The insert is
/// unconditional, the same as the detached compare-and-set path in
/// TypeScript.
pub fn set_detached(
  state: ClaimsState,
  key: String,
  value: Json,
) -> ClaimsState {
  ClaimsState(
    ..state,
    claims: dict.insert(state.claims, key, ClaimEntry(value, 0)),
  )
}

/// The acceptance rule, which is S3 and S4. The function applies it in the
/// same way to a local operation and to a remote operation. It accepts the
/// operation if the key is unclaimed, or if the `ref_seq` of the operation
/// equals the sequence number of the committed entry *exactly*. On an accept,
/// it replaces the entry with the value of the operation and the sequence
/// number of the operation. It returns whether it accepted the operation, so
/// that a caller can emit an event or resolve an outcome.
fn apply_sequenced(
  state: ClaimsState,
  operation: ClaimOperation,
  seq: Int,
) -> #(ClaimsState, Bool) {
  let Claim(key, value, ref_seq) = operation
  let accepted = case dict.get(state.claims, key) {
    Error(_) -> True
    Ok(ClaimEntry(_, entry_seq)) -> ref_seq == entry_seq
  }
  case accepted {
    False -> #(state, False)
    True -> #(
      ClaimsState(
        ..state,
        claims: dict.insert(state.claims, key, ClaimEntry(value, seq)),
      ),
      True,
    )
  }
}

/// Apply a sequenced operation from another client. An accepted operation
/// replaces the entry and emits `Claimed(key, False)`. A refused operation
/// changes no state and emits nothing. A remote operation that wins a key with
/// a local pending claim does not change that pending entry, which is rule S10.
/// That entry resolves only when the local operation sequences.
pub fn apply_remote(
  state: ClaimsState,
  operation: ClaimOperation,
  seq: Int,
) -> #(ClaimsState, List(ClaimEvent)) {
  let #(state, accepted) = apply_sequenced(state, operation, seq)
  case accepted {
    True -> #(state, [Claimed(operation.key, False)])
    False -> #(state, [])
  }
}

/// The local operation returns sequenced. The acceptance rule is the same as in
/// `apply_remote`. The function also removes the pending entry for the key and
/// resolves its outcome. The outcome is `Accepted`, with the submitted value,
/// if the claim won. Otherwise it is `Lost`, with the current committed value,
/// which can be absent. Unlike the map kernel and the counter kernel, an ack
/// here emits `Claimed(key, True)`, because the kernel showed nothing
/// optimistically at submit time.
///
/// The function is strict. An ack with no matching pending entry is a routing
/// fault, and not an acceptable condition.
pub fn ack_local(
  state: ClaimsState,
  operation: ClaimOperation,
  seq: Int,
) -> Result(#(ClaimsState, List(ClaimEvent), ClaimOutcome), KernelError) {
  case dict.get(state.pending, operation.key) {
    Error(_) ->
      Error(UnexpectedAck(
        operation,
        "no pending claim for key \"" <> operation.key <> "\"",
      ))
    Ok(pending_value) -> {
      let #(state, accepted) = apply_sequenced(state, operation, seq)
      let state =
        ClaimsState(..state, pending: dict.delete(state.pending, operation.key))
      case accepted {
        True ->
          Ok(#(state, [Claimed(operation.key, True)], Accepted(pending_value)))
        False ->
          Ok(#(state, [], Lost(option.from_result(get(state, operation.key)))))
      }
    }
  }
}

/// Roll back a pending local operation. The function removes its pending entry
/// and resolves the outcome as `Aborted`. It is strict about a missing pending
/// entry. The TypeScript code accepts that condition.
pub fn rollback(
  state: ClaimsState,
  operation: ClaimOperation,
) -> Result(#(ClaimsState, ClaimOutcome), KernelError) {
  case dict.has_key(state.pending, operation.key) {
    True ->
      Ok(#(
        ClaimsState(..state, pending: dict.delete(state.pending, operation.key)),
        Aborted,
      ))
    False ->
      Error(UnexpectedRollback(
        operation,
        "no pending claim for key \"" <> operation.key <> "\"",
      ))
  }
}

/// Register a stashed operation as pending again, which guards the key. No
/// caller waits on it. The function returns the operation without a change, for
/// the resubmission, and it keeps the original `ref_seq`. It returns an error
/// if the key is already pending.
pub fn apply_stashed_operation(
  state: ClaimsState,
  operation: ClaimOperation,
) -> Result(#(ClaimsState, ClaimOperation), KernelError) {
  case dict.has_key(state.pending, operation.key) {
    True -> Error(AlreadyPendingLocally(operation.key))
    False ->
      Ok(#(
        ClaimsState(
          ..state,
          pending: dict.insert(state.pending, operation.key, operation.value),
        ),
        operation,
      ))
  }
}

/// Abort every pending claim, for example when the caller disposes the
/// channel. The function clears the pending claims and returns the aborted
/// keys, sorted, so that the result is deterministic. The runtime can then
/// resolve each waiting caller with `Aborted`.
pub fn abort_all(state: ClaimsState) -> #(ClaimsState, List(String)) {
  let keys = dict.keys(state.pending) |> list.sort(string.compare)
  #(ClaimsState(..state, pending: dict.new()), keys)
}

/// The values of the pending claims, for the handle scan during a garbage
/// collection. `summary_entries` gives the committed values.
pub fn pending_values(state: ClaimsState) -> List(Json) {
  dict.values(state.pending)
}
