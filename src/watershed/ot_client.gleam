//// The generic client-transform substrate that the operational transform (OT)
//// kernels share. Those kernels run on the central sequencer of watershed,
//// which does not transform. This module was extracted from
//// `json_ot_kernel.gleam`, so that another kernel can use the same mechanics
//// without a copy of them.
////
//// Every helper here is parameterized over the concrete op type, the concrete
//// error type, and the `transform` callback of the kernel. This module knows
//// nothing about the component shape of json0, or of any other algebra. It
//// also does not put the kernel state into a generic container. Each kernel
//// keeps its own concrete state record, wire type, event type, and error type.
//// It uses only the mechanics below.
////
//// ## One op in flight (the Wave and ShareDB client model)
////
//// The sequencer never transforms. It broadcasts an op without a change, with
//// the reference sequence number (RSN) that the author wrote it against. A
//// receiver must thus transform that op past every op that sequenced in the
//// window `(op.ref_seq, op.seq)`, because the author did not see those ops.
////
//// For the context to stay consistent, no earlier unacked op of the same
//// author can come before the incoming op in that window. If one does, the
//// context of the incoming op already contains ops that the window replay does
//// not contain. This is the dOPT hazard.
////
//// A kernel prevents this condition. It keeps one op **in flight** at most,
//// and it composes the later optimistic edits into a buffer that it releases
//// only on an ack. The module doc of `json_ot_kernel` describes the full
//// procedure. `to_head_context` and `rebase_pending` below depend on that
//// invariant: the window that they fold over has no gap, because it contains
//// no entry from the same author.
////
//// ## The transform side comes from the sequence order
////
//// A transform of two concurrent ops needs a tie-break, which the algebras
//// here call the `Side`. Every replica must give the same side to the same
//// pair of ops, or the replicas do not converge.
////
//// The tie-break is the sequence order: **the op with the larger sequence
//// number is the later op**, and the other op is the earlier op. Each kernel
//// maps those two roles onto the `Side` values of its own algebra. The
//// sequencer supplies one total order to every replica, so this rule is the
//// same at every replica, and it needs no identity.
////
//// The rule holds for a pending local op, which has no sequence number yet.
//// A client receives the sequenced stream in order, so an op that the client
//// did not send, or did send but is not acked, always sequences after every
//// op that the client processes now. A pending op is thus always the later
//// op.
////
//// An identity is not usable for this tie-break. The client id of a replica
//// changes on a reconnect, so an op can go on the wire under one id after the
//// author already rebased it under another id. The two replicas then give
//// opposite sides to the same pair, and the document forks.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

// ─────────────────────────────────────────────────────────────────────────────
// Concurrency-window transform
// ─────────────────────────────────────────────────────────────────────────────

/// A sequenced op that the kernel keeps for the concurrency window. The kernel
/// already transformed it into the context that it was applied in, which is
/// the head context at its `seq`.
pub type LogEntry(op) {
  LogEntry(seq: Int, op: op)
}

/// Fold an incoming op past every logged entry that sequenced inside its
/// `(ref_seq, seq)` window, in seq order. The function uses
/// `transform_against` to advance the op past each entry. The incoming op has
/// a larger sequence number than every entry in the window, so the closure of
/// the kernel must give the incoming op the side of the later op.
///
/// The one-op-in-flight invariant means that no entry in the window has the
/// author of the incoming op. The window thus has no gap, and this function
/// puts the op into head context.
pub fn to_head_context(
  log: List(LogEntry(op)),
  ref_seq: Int,
  seq: Int,
  op: op,
  transform_against: fn(op, LogEntry(op)) -> Result(op, error),
) -> Result(op, error) {
  log
  |> list.filter(fn(e) { e.seq > ref_seq && e.seq < seq })
  |> list.sort(fn(a, b) { int.compare(a.seq, b.seq) })
  |> list.try_fold(op, transform_against)
}

// ─────────────────────────────────────────────────────────────────────────────
// Unacknowledged local edits
// ─────────────────────────────────────────────────────────────────────────────

/// The local edits that wait for an acknowledgement.
///
/// A buffered edit exists only behind an op that is already on the wire. This
/// type states that rule, so a kernel cannot hold a buffer with an empty wire
/// slot.
pub type Pending(op) {
  /// No local op waits for an acknowledgement.
  Idle
  /// One op is on the wire. The op is written against the sequenced state.
  InFlight(op: op)
  /// One op is on the wire, and every later local edit is composed into
  /// `buffered`. `buffered` is written against the sequenced state with `op`
  /// applied.
  InFlightAndBuffered(op: op, buffered: op)
}

/// The op that is on the wire. The result is `Error(Nil)` when no op waits for
/// an acknowledgement.
pub fn in_flight(pending: Pending(op)) -> Result(op, Nil) {
  case pending {
    Idle -> Error(Nil)
    InFlight(op) -> Ok(op)
    InFlightAndBuffered(op, _) -> Ok(op)
  }
}

/// The composed local edits that wait behind the op on the wire. The result is
/// `Error(Nil)` when there is no such edit.
pub fn buffered(pending: Pending(op)) -> Result(op, Nil) {
  case pending {
    Idle -> Error(Nil)
    InFlight(_) -> Error(Nil)
    InFlightAndBuffered(_, buffered) -> Ok(buffered)
  }
}

/// Record a local edit. The edit becomes the op on the wire when the wire slot
/// is free. The edit joins the buffer in every other case, through `compose`.
/// The second element of the result is the op to send, and it is `None` when
/// the kernel must hold the edit.
pub fn hold_local(
  pending: Pending(op),
  edit: op,
  compose: fn(op, op) -> Result(op, error),
) -> Result(#(Pending(op), Option(op)), error) {
  case pending {
    Idle -> Ok(#(InFlight(edit), Some(edit)))
    InFlight(op) -> Ok(#(InFlightAndBuffered(op, edit), None))
    InFlightAndBuffered(op, buffered) -> {
      use composed <- result.try(compose(buffered, edit))
      Ok(#(InFlightAndBuffered(op, composed), None))
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending-op rebase
// ─────────────────────────────────────────────────────────────────────────────

/// Rebase every unacknowledged local op past an incoming remote op. The
/// function returns the rebased local ops and the remote op advanced past all
/// of them. The visible remote event of the kernel must use that advanced op.
///
/// The kernel rebases the op on the wire first, and then the buffer, which
/// lives one context deeper. The function advances the remote op past each
/// layer in that order, so every rebase is well formed.
///
/// A pending local op sequences after the remote op, because the client reads
/// the sequenced stream in order. The `rebase_local` closure must thus give the
/// local op the side of the later op, and `advance_remote` must give the remote
/// op the side of the earlier op.
pub fn rebase_pending(
  pending: Pending(op),
  remote: op,
  rebase_local: fn(op, op) -> Result(op, error),
  advance_remote: fn(op, op) -> Result(op, error),
) -> Result(#(Pending(op), op), error) {
  case pending {
    Idle -> Ok(#(Idle, remote))
    InFlight(op) -> {
      use rebased <- result.try(rebase_local(op, remote))
      use advanced <- result.try(advance_remote(remote, op))
      Ok(#(InFlight(rebased), advanced))
    }
    InFlightAndBuffered(op, buffered) -> {
      use rebased_op <- result.try(rebase_local(op, remote))
      use after_op <- result.try(advance_remote(remote, op))
      use rebased_buffer <- result.try(rebase_local(buffered, after_op))
      use advanced <- result.try(advance_remote(after_op, buffered))
      Ok(#(InFlightAndBuffered(rebased_op, rebased_buffer), advanced))
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Concurrency-log GC
// ─────────────────────────────────────────────────────────────────────────────

/// Drop the log entries that no future window can contain. The `ref_seq` of an
/// op is the minimum sequence number (MSN) or more, so an entry at the MSN or
/// below it is dead.
pub fn gc_log(log: List(LogEntry(op)), msn: Int) -> List(LogEntry(op)) {
  list.filter(log, fn(e) { e.seq > msn })
}

// ─────────────────────────────────────────────────────────────────────────────
// Single-inflight / buffer promotion
// ─────────────────────────────────────────────────────────────────────────────

/// Retire the op that the server acknowledged. A buffered edit becomes the next
/// op on the wire, and the function builds its wire envelope. The reference
/// sequence of that envelope is the `seq` of the acknowledgement, because the
/// buffer is written against `sequenced` with the acknowledged op applied.
///
/// The second element of the result is `None` when there was no buffered edit.
/// This is a plain function over a `Pending` value and a wire constructor, and
/// not over kernel state, so every kernel can share it whatever the shape of
/// its state record is.
pub fn promote_buffer(
  pending: Pending(op),
  seq: Int,
  make_wire: fn(Int, op) -> wire,
) -> #(Pending(op), Option(wire)) {
  case pending {
    Idle -> #(Idle, None)
    InFlight(_) -> #(Idle, None)
    InFlightAndBuffered(_, buffered) -> #(
      InFlight(buffered),
      Some(make_wire(seq, buffered)),
    )
  }
}

/// Take the value from a pending `Option` slot, for example the `outbound`
/// field of a kernel. The function returns the value, if there is one, and the
/// empty slot. A second call has no more effect.
pub fn take_pending(pending: Option(a)) -> #(Option(a), Option(a)) {
  case pending {
    None -> #(None, None)
    Some(value) -> #(None, Some(value))
  }
}
