//// Stateful client-transform kernel over the pure json0 algebra in
//// `json_ot.gleam`, riding watershed's central sequencer. Same discipline as
//// `map_kernel.gleam`: no process, no side effects — every operation returns
//// the new state plus the events it produced. The runtime actor owns
//// sequencing (SN/RSN, FIFO ack matching); the kernel assumes acks arrive in
//// submission order.
////
//// ## Single op in flight (the Wave/ShareDB client model)
////
//// levee never transforms (the sequencer is kernel-agnostic), so an op is
//// broadcast verbatim with the reference sequence number (RSN) it was authored
//// against, and a receiver must transform it past every op sequenced in
//// `(op.ref_seq, op.seq)` its author had not seen. For that to be
//// context-consistent, an op must never be preceded in that window by an
//// *earlier unacked op of the same author* — otherwise the incoming op's
//// context already includes ops the window replay does not (the classic dOPT
//// hazard).
////
//// We guarantee this by keeping at most one op **in flight**: `inflight` is the
//// single unacked op on the wire (authored against `sequenced`), and `buffer`
//// composes every optimistic edit made since, released as the next `inflight`
//// only when `inflight` is acked. Because a client's previous op is always
//// acked before its next is sent, no window ever contains a same-author op, so
//// transforming an incoming op past *all* logged ops in its window is correct.
////
//// `side` is derived from author identity (design decision #4): for any pair of
//// ops the client with the smaller id is `Lft`, so every replica breaks
//// insert-at-same-index ties identically and TP1 convergence holds.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/json_ot.{
  type JsonValue, type Op, type PathKey, type Side, Lft, Rgt,
}
import watershed/ot_client.{LogEntry}

/// A sequenced op remembered for the concurrency window, already transformed
/// into the context it was applied in (head context at its `seq`). An alias
/// for `ot_client`'s shared log-entry shape, concretized to json0's `Op`.
type LogEntry =
  ot_client.LogEntry(Op)

/// Server-confirmed document, the concurrency-window `log`, and the single
/// in-flight op plus a composed buffer of later optimistic edits.
pub type JsonOtState {
  JsonOtState(
    /// This client's sequencing identity, for the `side` tie-break.
    self: Int,
    /// Server-confirmed document (all sequenced ops applied in order).
    sequenced: JsonValue,
    /// Sequenced ops in head context, oldest first, kept while they can still
    /// fall inside some future op's `(ref_seq, seq)` window (seq > MSN).
    log: List(LogEntry),
    /// The one unacked op on the wire, expressed against `sequenced` (rebased
    /// as remote ops arrive). `None` when nothing is in flight.
    inflight: Option(Op),
    /// Optimistic edits authored since `inflight` was sent, composed into one
    /// op expressed against `sequenced` ∘ `inflight`. Released as the next
    /// `inflight` on ack. `None` when empty.
    buffer: Option(Op),
    /// A buffer just released as the new `inflight` on ack and awaiting
    /// dispatch on the wire. Drained by `take_outbound`; the runtime cannot
    /// send it inline because acks are processed while ingesting a sequenced
    /// message. `None` when there is nothing pending to send.
    outbound: Option(JsonOtWireOp),
  )
}

/// An op as it travels on the wire: the components plus the reference sequence
/// number they were authored against (needed to rebuild the receiver's
/// concurrency window). `author`/`seq` are stamped by the sequencer envelope.
pub type JsonOtWireOp {
  JsonOtWireOp(ref_seq: Int, components: Op)
}

/// Emitted whenever the observable document changes. One per op component.
pub type JsonOtEvent {
  DocChanged(path: List(PathKey), local: Bool)
}

pub type KernelError {
  /// An ack arrived with nothing in flight.
  UnexpectedAck(detail: String)
  /// The pure algebra rejected an apply/transform (bad path, bad value, …).
  OtFailure(err: json_ot.OtError)
}

// ─────────────────────────────────────────────────────────────────────────────
// Construction / summary round-trip
// ─────────────────────────────────────────────────────────────────────────────

/// A fresh kernel for client `self` over an empty object document.
pub fn new(self: Int) -> JsonOtState {
  from_value(self, json_ot.VObject([]))
}

/// A fresh kernel seeded with an initial document value.
pub fn from_value(self: Int, doc: JsonValue) -> JsonOtState {
  JsonOtState(
    self: self,
    sequenced: doc,
    log: [],
    inflight: None,
    buffer: None,
    outbound: None,
  )
}

/// Load a sequenced-only state from a stored summary under identity `self`. No
/// local edits are ever summarized, and the concurrency window starts empty.
pub fn from_summary(self: Int, doc: JsonValue) -> JsonOtState {
  from_value(self, doc)
}

/// The confirmed document a summary captures — sequenced only, no local edits.
pub fn summary(state: JsonOtState) -> JsonValue {
  state.sequenced
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

/// The optimistic document: `sequenced` with `inflight` then `buffer` applied.
pub fn view(state: JsonOtState) -> Result(JsonValue, KernelError) {
  use after_inflight <- result.try(apply_opt(state.sequenced, state.inflight))
  apply_opt(after_inflight, state.buffer)
}

fn apply_opt(doc: JsonValue, op: Option(Op)) -> Result(JsonValue, KernelError) {
  case op {
    None -> Ok(doc)
    Some(op) -> apply_op(doc, op)
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure re-exports (KernelError-wrapped) shared by local + remote paths
// ─────────────────────────────────────────────────────────────────────────────

/// Apply an op to a document (json0 J2–J4).
pub fn apply_op(doc: JsonValue, op: Op) -> Result(JsonValue, KernelError) {
  json_ot.apply(doc, op) |> result.map_error(OtFailure)
}

/// Transform `a` past `b` for the given side (json0 J5–J8, TP1).
pub fn transform(a: Op, b: Op, side: Side) -> Result(Op, KernelError) {
  json_ot.transform(a, b, side) |> result.map_error(OtFailure)
}

/// Compose two consecutive ops into one (json0 J9): `b` applied after `a`.
pub fn compose(a: Op, b: Op) -> Op {
  list.append(a, b)
}

/// Invert an op using the pre-images its `od`/`ld` components already carry.
pub fn invert(op: Op) -> Op {
  json_ot.invert(op)
}

// ─────────────────────────────────────────────────────────────────────────────
// Local operations (optimistic apply + outbound op)
// ─────────────────────────────────────────────────────────────────────────────

/// Author a local edit against the current optimistic view. If nothing is in
/// flight the edit becomes `inflight` and is returned as a wire op to send
/// (stamped with `ref_seq`, the client's last-delivered SN). Otherwise it is
/// composed into `buffer` and held until the in-flight op is acked, so at most
/// one op is ever on the wire; `Ok(#(state, None, events))` signals "nothing to
/// send yet".
pub fn submit(
  state: JsonOtState,
  components: Op,
  ref_seq: Int,
) -> Result(
  #(JsonOtState, Option(JsonOtWireOp), List(JsonOtEvent)),
  KernelError,
) {
  use current <- result.try(view(state))
  use _ <- result.try(apply_op(current, components))
  case state.inflight {
    None -> {
      let state = JsonOtState(..state, inflight: Some(components))
      Ok(#(
        state,
        Some(JsonOtWireOp(ref_seq, components)),
        events_for(components, True),
      ))
    }
    Some(_) -> {
      let buffer = case state.buffer {
        None -> components
        Some(b) -> compose(b, components)
      }
      let state = JsonOtState(..state, buffer: Some(buffer))
      Ok(#(state, None, events_for(components, True)))
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Remote operations
// ─────────────────────────────────────────────────────────────────────────────

/// Apply a sequenced op authored by another client. `seq` is its sequence
/// number, `author` its client id, `msn` the minimum sequence number (log GC).
/// We transform the op into head context past every op sequenced in
/// `(ref_seq, seq)` — none of which can be the author's own (single in-flight),
/// so the window is gap-free — apply it, log it, then rebase `inflight` and
/// `buffer` past it.
pub fn apply_remote(
  state: JsonOtState,
  wire: JsonOtWireOp,
  seq: Int,
  author: Int,
  msn: Int,
) -> Result(#(JsonOtState, List(JsonOtEvent)), KernelError) {
  use op_head <- result.try(
    ot_client.to_head_context(
      state.log,
      wire.ref_seq,
      seq,
      wire.components,
      fn(current, e) { transform(current, e.op, side_of(author, e.author)) },
    ),
  )
  use sequenced <- result.try(apply_op(state.sequenced, op_head))
  // Rebase the in-flight op, then the buffer (which lives one context deeper),
  // advancing the remote op past each so the next rebase is well-formed.
  use #(inflight, remote_after_inflight) <- result.try(
    ot_client.rebase_pending(
      state.inflight,
      op_head,
      fn(local, remote) {
        transform(local, remote, side_of(state.self, author))
      },
      fn(remote, local) {
        transform(remote, local, side_of(author, state.self))
      },
    ),
  )
  use #(buffer, _remote_after_buffer) <- result.try(
    ot_client.rebase_pending(
      state.buffer,
      remote_after_inflight,
      fn(local, remote) {
        transform(local, remote, side_of(state.self, author))
      },
      fn(remote, local) {
        transform(remote, local, side_of(author, state.self))
      },
    ),
  )
  let log =
    ot_client.gc_log(
      list.append(state.log, [LogEntry(seq, author, op_head)]),
      msn,
    )
  let state =
    JsonOtState(
      ..state,
      sequenced: sequenced,
      log: log,
      inflight: inflight,
      buffer: buffer,
    )
  Ok(#(state, events_for(op_head, False)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Acks (own ops coming back sequenced)
// ─────────────────────────────────────────────────────────────────────────────

/// Commit our own op now that the server has sequenced it. The op is the
/// current `inflight`, already rebased past every concurrent remote op, so we
/// apply it to `sequenced` and log it in head context. The `buffer` (if any) is
/// released as the next `inflight` and stashed in `outbound` — stamped with
/// `ref_seq = seq`, since the buffer is expressed against `sequenced` with our
/// just-acked op applied — for the runtime to dispatch via `take_outbound`. The
/// optimistic view is unchanged, so no events are emitted.
///
/// The `_wire` echoed by the sequencer is the original op we submitted; since
/// the sequencer never transforms it will not match the rebased in-flight op,
/// so it is ignored beyond FIFO ordering.
pub fn ack_local(
  state: JsonOtState,
  _wire: JsonOtWireOp,
  seq: Int,
  msn: Int,
) -> Result(#(JsonOtState, List(JsonOtEvent)), KernelError) {
  case state.inflight {
    None -> Error(UnexpectedAck("ack with nothing in flight"))
    Some(inflight) -> {
      use sequenced <- result.try(apply_op(state.sequenced, inflight))
      let log =
        ot_client.gc_log(
          list.append(state.log, [LogEntry(seq, state.self, inflight)]),
          msn,
        )
      // Release the buffer as the next in-flight op, if any.
      let #(next_inflight, to_send) =
        ot_client.promote_buffer(state.buffer, seq, JsonOtWireOp)
      let state =
        JsonOtState(
          ..state,
          sequenced: sequenced,
          log: log,
          inflight: next_inflight,
          buffer: None,
          outbound: to_send,
        )
      Ok(#(state, []))
    }
  }
}

/// Drain any op released onto the wire by `ack_local` (a buffer promoted to the
/// new in-flight op). Returns the op to dispatch and clears the pending slot;
/// `None` when nothing is waiting. Idempotent once drained.
pub fn take_outbound(
  state: JsonOtState,
) -> #(JsonOtState, Option(JsonOtWireOp)) {
  let #(outbound, taken) = ot_client.take_pending(state.outbound)
  #(JsonOtState(..state, outbound: outbound), taken)
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// The transform side for `x` when transformed past a `y` authored elsewhere:
/// the op whose author has the smaller id is `Lft`. Symmetric and replicated,
/// so every client breaks the same tie the same way.
fn side_of(author_x: Int, author_y: Int) -> Side {
  case ot_client.author_precedes(author_x, author_y) {
    True -> Lft
    False -> Rgt
  }
}

fn events_for(op: Op, local: Bool) -> List(JsonOtEvent) {
  list.map(op, fn(component) { DocChanged(component.path, local) })
}
