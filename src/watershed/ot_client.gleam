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

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

// ─────────────────────────────────────────────────────────────────────────────
// Deterministic author precedence
// ─────────────────────────────────────────────────────────────────────────────

/// A deterministic tie-break between two authors. The result is `True` when
/// `author_x` comes before `author_y`, which is when its client id is smaller.
///
/// The function is symmetric and replicated, so every replica breaks the same
/// insert-at-the-same-index tie in the same way. A kernel maps the result onto
/// the `Side` type of its own algebra, for example the `Lft` and `Rgt` values
/// of json0.
pub fn author_precedes(author_x: Int, author_y: Int) -> Bool {
  author_x < author_y
}

// ─────────────────────────────────────────────────────────────────────────────
// Concurrency-window transform
// ─────────────────────────────────────────────────────────────────────────────

/// A sequenced op that the kernel keeps for the concurrency window. The kernel
/// already transformed it into the context that it was applied in, which is
/// the head context at its `seq`.
pub type LogEntry(op) {
  LogEntry(seq: Int, author: Int, op: op)
}

/// Fold an incoming op past every logged entry that sequenced inside its
/// `(ref_seq, seq)` window, in seq order. The function uses
/// `transform_against` to advance the op past each entry. The closure of the
/// kernel must derive its own `Side` value from `author_precedes`, applied to
/// the incoming author and to `entry.author`.
///
/// The one-op-in-flight invariant means that no entry in the window has the
/// author of the incoming op. The window thus has no gap, and this function
/// puts the op into head context.
pub fn to_head_context(
  log: List(LogEntry(op)),
  ref_seq: Int,
  seq: Int,
  op: op,
  transform_against: fn(op, LogEntry(op)) -> Result(op, err),
) -> Result(op, err) {
  log
  |> list.filter(fn(e) { e.seq > ref_seq && e.seq < seq })
  |> list.sort(fn(a, b) { seq_compare(a.seq, b.seq) })
  |> list.try_fold(op, transform_against)
}

fn seq_compare(a: Int, b: Int) -> order.Order {
  case a < b {
    True -> order.Lt
    False ->
      case a > b {
        True -> order.Gt
        False -> order.Eq
      }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending-op rebase
// ─────────────────────────────────────────────────────────────────────────────

/// Rebase an optional pending local op, which is `inflight` or `buffer`, past
/// an incoming remote op. The function returns the rebased local op and the
/// remote op advanced past it. The next pending layer must transform against
/// that advanced remote op, and so must the visible remote event of the
/// kernel.
///
/// The local result is `None` when there is no pending op to rebase. The
/// function then returns the remote op without a change.
pub fn rebase_pending(
  local: Option(op),
  remote: op,
  rebase_local: fn(op, op) -> Result(op, err),
  advance_remote: fn(op, op) -> Result(op, err),
) -> Result(#(Option(op), op), err) {
  case local {
    None -> Ok(#(None, remote))
    Some(local) -> {
      use rebased <- result.try(rebase_local(local, remote))
      use advanced <- result.try(advance_remote(remote, local))
      Ok(#(Some(rebased), advanced))
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

/// Release a buffered op as the next in-flight op after an ack. The function
/// sets the reference sequence of the wire envelope to the `seq` of the ack,
/// because the buffer is expressed against `sequenced` with the acked op
/// applied.
///
/// The result is the new `inflight` and `outbound` pair. It is `#(None, None)`
/// when the buffer was empty. This is a plain function over an `Option` and a
/// wire constructor, and not over kernel state, so every kernel can share it
/// whatever the shape of its state record is.
pub fn promote_buffer(
  buffer: Option(op),
  seq: Int,
  make_wire: fn(Int, op) -> wire,
) -> #(Option(op), Option(wire)) {
  case buffer {
    None -> #(None, None)
    Some(buffer) -> #(Some(buffer), Some(make_wire(seq, buffer)))
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
