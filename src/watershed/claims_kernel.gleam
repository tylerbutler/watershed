//// Pure port of FluidFramework's `packages/dds/claims/src/claims.ts`.
////
//// Claims is a first-writer-wins key/value DDS with per-key sequence-number
//// compare-and-set. Two properties make it a distinct kernel from counter/map,
//// and both simplify it:
////
//// 1. **Reads are NOT optimistic.** `get`/`has` return only committed state. A
////    pending local claim is invisible until it wins — there is no
////    pending-overlay/rebase machinery, the inverse of `map_kernel`.
//// 2. **Acceptance is decided at sequencing time, identically for local and
////    remote ops** (`apply_sequenced`): the key is unclaimed, or the op's
////    `ref_seq` exactly equals the committed entry's sequence number. Every
////    client evaluates the same rule against the same committed state, so
////    convergence is by construction; the local path only additionally
////    resolves the caller's pending outcome.
////
//// The genuinely new pattern is the **deferred outcome**: a local claim's
//// result ("did I win?") is unknowable until the op round-trips. The TS class
//// hands back a `Promise`; this pure kernel returns a `ClaimOutcome` from
//// `ack_local`/`rollback`/`abort_all` and lets the runtime own the async
//// surface. `last_seen_seq` is a parameter, not kernel state: the runtime
//// actor owns sequencing concerns (as it does for map), and it already tracks
//// the container's last sequence number.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type ClaimsState {
  ClaimsState(
    /// Committed claims: value + the sequence number of the op that set it.
    claims: Dict(String, ClaimEntry),
    /// Pending local claims keyed by claim key — at most one per key. The
    /// value is the submitted value, needed to build the `Accepted` outcome
    /// and for handle scanning. No queue: acceptance is decided by the
    /// sequenced op itself, not by pending-queue position.
    pending: Dict(String, Json),
  )
}

pub type ClaimEntry {
  ClaimEntry(value: Json, sequence_number: Int)
}

/// The one claim op as it travels over the wire. Both write-once
/// (`try_set_claim`) and CAS (`compare_and_set_claim`) share this shape.
pub type ClaimOp {
  Claim(key: String, value: Json, ref_seq: Int)
}

pub type ClaimEvent {
  /// Emitted whenever a sequenced op is accepted. `local` follows the
  /// watershed convention (map/counter events carry it; the TS event doesn't).
  Claimed(key: String, local: Bool)
}

/// Synchronous result of `try_set_claim` / `compare_and_set_claim`.
pub type SubmitResult {
  /// The op must be sent; its outcome arrives later via `ack_local`
  /// (the TS "Pending" status).
  Submitted(state: ClaimsState, op: ClaimOp)
  /// `try_set_claim` found a committed entry — nothing is sent. Carries the
  /// committed value (which may be JSON null).
  AlreadyClaimed(current_value: Json)
}

/// The resolved outcome of a pending claim, returned once its op sequences (or
/// is rolled back / aborted) for the runtime to deliver to whoever is waiting.
/// Replaces the TS promise.
pub type ClaimOutcome {
  Accepted(value: Json)
  /// Lost the race. Carries the current committed value; `None` only if the
  /// key ended up genuinely unclaimed (the TS `T | undefined`). In practice a
  /// loss implies a committed winner, so this is `Some` — the `Option` mirrors
  /// the upstream type rather than a reachable-in-isolation state.
  Lost(current_value: Option(Json))
  Aborted
}

pub type KernelError {
  /// Submit-side usage error — the TS `UsageError`, surfaced as data.
  AlreadyPendingLocally(key: String)
  /// A local ack arrived with no matching pending entry. The TS code tolerates
  /// this silently; the kernel is strict, matching counter/map's philosophy
  /// that a routing mismatch is fatal divergence.
  UnexpectedAck(op: ClaimOp, detail: String)
  UnexpectedRollback(op: ClaimOp, detail: String)
}

pub fn new() -> ClaimsState {
  ClaimsState(claims: dict.new(), pending: dict.new())
}

/// Build a committed-only state from stored summary triples `(key, value,
/// sequence_number)`. Sequence numbers are persisted so CAS `ref_seq` matching
/// keeps working after load. A freshly loaded state has no pending entries.
pub fn from_summary(entries: List(#(String, Json, Int))) -> ClaimsState {
  let claims =
    list.fold(entries, dict.new(), fn(acc, entry) {
      let #(key, value, seq) = entry
      dict.insert(acc, key, ClaimEntry(value, seq))
    })
  ClaimsState(claims: claims, pending: dict.new())
}

/// The committed claims to store in a summary, as `(key, value,
/// sequence_number)` triples sorted by key for stable snapshots.
pub fn summary_entries(state: ClaimsState) -> List(#(String, Json, Int)) {
  dict.to_list(state.claims)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(entry) {
    let #(key, ClaimEntry(value, seq)) = entry
    #(key, value, seq)
  })
}

/// The committed value for a key, or `None` if unclaimed. Committed-only by
/// design: a pending local claim is invisible until it wins.
pub fn get(state: ClaimsState, key: String) -> Option(Json) {
  case dict.get(state.claims, key) {
    Ok(ClaimEntry(value, _)) -> Some(value)
    Error(_) -> None
  }
}

/// Whether a committed claim exists for a key. Distinguishes "never set" from
/// "set to JSON null". Committed-only, like `get`.
pub fn has(state: ClaimsState, key: String) -> Bool {
  dict.has_key(state.claims, key)
}

/// Write-once submit. If a committed entry exists, returns `AlreadyClaimed`
/// synchronously with no op sent. Otherwise behaves as a CAS against the
/// unclaimed key, capturing `ref_seq = last_seen_seq`.
///
/// The committed check runs *before* the pending guard, so a try-set on a
/// committed key returns `AlreadyClaimed` even when a CAS for that key is
/// pending locally.
pub fn try_set_claim(
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

/// CAS submit. Captures `ref_seq` from the committed entry's sequence number
/// if the key is claimed, else `last_seen_seq`. Always submits (never returns
/// `AlreadyClaimed` synchronously); acceptance is decided when the op
/// sequences.
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

/// Detached apply: no other clients exist, so apply the claim directly with
/// sequence number 0. The runtime decides when the channel is detached (as it
/// does for map). Unconditional insert, mirroring the TS CAS detached path.
pub fn set_detached(
  state: ClaimsState,
  key: String,
  value: Json,
) -> ClaimsState {
  ClaimsState(..state, claims: dict.insert(state.claims, key, ClaimEntry(value, 0)))
}

/// The acceptance rule (S3/S4), applied identically for local and remote ops:
/// accept iff the key is unclaimed or the op's `ref_seq` *exactly* equals the
/// committed entry's sequence number. On accept, overwrite the entry with the
/// op's value and the op's own sequence number. Returns whether it was
/// accepted so callers can emit events / resolve outcomes.
fn apply_sequenced(
  state: ClaimsState,
  op: ClaimOp,
  seq: Int,
) -> #(ClaimsState, Bool) {
  let Claim(key, value, ref_seq) = op
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

/// Apply a sequenced op from another client. Accepted ops overwrite the entry
/// and emit `Claimed(key, False)`; rejected ops leave state unchanged and emit
/// nothing. A remote op winning a key we have a pending claim on does not
/// disturb our pending entry (S10) — it resolves only when our own op
/// sequences.
pub fn apply_remote(
  state: ClaimsState,
  op: ClaimOp,
  seq: Int,
) -> #(ClaimsState, List(ClaimEvent)) {
  let #(state, accepted) = apply_sequenced(state, op, seq)
  case accepted {
    True -> #(state, [Claimed(op.key, False)])
    False -> #(state, [])
  }
}

/// Our own local op comes back sequenced. Acceptance is identical to
/// `apply_remote`; additionally the pending entry for the key is removed and
/// its outcome resolved: `Accepted` (with the submitted value) if it won, else
/// `Lost` (with the current committed value, which may be absent). Unlike
/// map/counter, acks emit `Claimed(key, True)` here, because nothing was shown
/// optimistically at submit time.
///
/// Strict: an ack with no matching pending entry is a routing bug, not a
/// tolerated edge case.
pub fn ack_local(
  state: ClaimsState,
  op: ClaimOp,
  seq: Int,
) -> Result(#(ClaimsState, List(ClaimEvent), ClaimOutcome), KernelError) {
  case dict.get(state.pending, op.key) {
    Error(_) ->
      Error(UnexpectedAck(op, "no pending claim for key \"" <> op.key <> "\""))
    Ok(pending_value) -> {
      let #(state, accepted) = apply_sequenced(state, op, seq)
      let state =
        ClaimsState(..state, pending: dict.delete(state.pending, op.key))
      case accepted {
        True -> Ok(#(state, [Claimed(op.key, True)], Accepted(pending_value)))
        False -> Ok(#(state, [], Lost(get(state, op.key))))
      }
    }
  }
}

/// Roll back a pending local op: remove its pending entry and resolve
/// `Aborted`. Strict on a missing pending entry (the TS code tolerates it).
pub fn rollback(
  state: ClaimsState,
  op: ClaimOp,
) -> Result(#(ClaimsState, ClaimOutcome), KernelError) {
  case dict.has_key(state.pending, op.key) {
    True ->
      Ok(#(
        ClaimsState(..state, pending: dict.delete(state.pending, op.key)),
        Aborted,
      ))
    False ->
      Error(UnexpectedRollback(
        op,
        "no pending claim for key \"" <> op.key <> "\"",
      ))
  }
}

/// Re-register a stashed op as pending (guarding the key; no caller awaits) and
/// return the op verbatim for resubmission — the original `ref_seq` is
/// preserved. Errors if the key is already pending.
pub fn apply_stashed_op(
  state: ClaimsState,
  op: ClaimOp,
) -> Result(#(ClaimsState, ClaimOp), KernelError) {
  case dict.has_key(state.pending, op.key) {
    True -> Error(AlreadyPendingLocally(op.key))
    False ->
      Ok(#(
        ClaimsState(
          ..state,
          pending: dict.insert(state.pending, op.key, op.value),
        ),
        op,
      ))
  }
}

/// Abort every pending claim (e.g. on dispose): clear pending and return the
/// aborted keys (sorted, for determinism) so the runtime can resolve each
/// waiter `Aborted`.
pub fn abort_all(state: ClaimsState) -> #(ClaimsState, List(String)) {
  let keys = dict.keys(state.pending) |> list.sort(string.compare)
  #(ClaimsState(..state, pending: dict.new()), keys)
}

/// Pending claim values, for handle scanning during GC. Committed values come
/// via `summary_entries`.
pub fn pending_values(state: ClaimsState) -> List(Json) {
  dict.values(state.pending)
}
