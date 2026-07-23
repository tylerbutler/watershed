//// Generic client-transform substrate shared by OT kernels riding
//// watershed's central (non-transforming) sequencer — extracted from
//// `json_ot_kernel.gleam` so a future `rich_text_kernel` can reuse the same
//// mechanics without duplicating them.
////
//// Every helper here is parameterized over the concrete op/error type and
//// the kernel's own `transform` callback: this module carries no knowledge
//// of json0's component shape (or any other algebra's), and does not wrap
//// kernel state in a generic container. Each kernel keeps its own concrete
//// state record, wire type, event type, and error type; it only borrows the
//// mechanics below.
////
//// ## Single op in flight (the Wave/ShareDB client model)
////
//// The sequencer never transforms, so an op is broadcast verbatim with the
//// reference sequence number (RSN) it was authored against, and a receiver
//// must transform it past every op sequenced in `(op.ref_seq, op.seq)` its
//// author had not seen. For that to be context-consistent, an op must never
//// be preceded in that window by an *earlier unacked op of the same
//// author* — otherwise the incoming op's context already includes ops the
//// window replay does not (the classic dOPT hazard).
////
//// A kernel guarantees this by keeping at most one op **in flight**, with
//// later optimistic edits composed into a buffer released only on ack — see
//// `json_ot_kernel`'s module doc for the full discipline. `to_head_context`
//// and `rebase_pending` below assume that invariant: the window they fold
//// over is gap-free (no same-author entries) precisely because of it.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

// ─────────────────────────────────────────────────────────────────────────────
// Deterministic author precedence
// ─────────────────────────────────────────────────────────────────────────────

/// Deterministic tie-break between two authors: `True` when `author_x`
/// precedes `author_y` (the smaller client id wins). Symmetric and
/// replicated, so every replica breaks the same insert-at-same-index tie the
/// same way — a kernel maps this onto its own algebra's `Side` type (json0's
/// `Lft`/`Rgt`, or a future algebra's equivalent).
pub fn author_precedes(author_x: Int, author_y: Int) -> Bool {
  author_x < author_y
}

// ─────────────────────────────────────────────────────────────────────────────
// Concurrency-window transform
// ─────────────────────────────────────────────────────────────────────────────

/// A sequenced op remembered for the concurrency window, already transformed
/// into the context it was applied in (head context at its `seq`).
pub type LogEntry(op) {
  LogEntry(seq: Int, author: Int, op: op)
}

/// Fold an incoming op past every logged entry sequenced strictly inside its
/// `(ref_seq, seq)` window, in seq order, using `transform_against` to
/// advance it past each entry (the kernel's closure is expected to derive
/// its own `Side` from `author_precedes` applied to the incoming author and
/// `entry.author`). Under the single-in-flight invariant none of these
/// entries share the incoming op's author, so the window is gap-free and
/// this lands the op in head context.
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

/// Rebase an optional pending local op (`inflight` or `buffer`) past an
/// incoming remote op, returning both the rebased local op and the remote op
/// advanced past it — the latter is what the next-deeper pending layer (and,
/// eventually, a kernel's visible remote event) must be transformed against.
/// `None` when there is no pending op to rebase, in which case the remote op
/// is returned unchanged.
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

/// Drop log entries that can no longer fall inside any future op's window:
/// an op's `ref_seq` is at least the MSN, so entries at or below the MSN are
/// dead.
pub fn gc_log(log: List(LogEntry(op)), msn: Int) -> List(LogEntry(op)) {
  list.filter(log, fn(e) { e.seq > msn })
}

// ─────────────────────────────────────────────────────────────────────────────
// Single-inflight / buffer promotion
// ─────────────────────────────────────────────────────────────────────────────

/// Release a buffered op as the next in-flight op after an ack, stamping the
/// wire envelope's reference sequence to the ack's `seq` (the buffer is
/// expressed against `sequenced` with the just-acked op applied). Returns the
/// new `inflight`/`outbound` pair; `#(None, None)` when nothing was
/// buffered. Left as a plain function over `Option`/a wire constructor (not
/// kernel state) so it stays safe to share without touching any kernel's
/// state record shape.
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

/// Drain a pending `Option` slot (e.g. a kernel's `outbound` field): returns
/// the value (if any) and the cleared slot. Idempotent once drained.
pub fn take_pending(pending: Option(a)) -> #(Option(a), Option(a)) {
  case pending {
    None -> #(None, None)
    Some(value) -> #(None, Some(value))
  }
}
