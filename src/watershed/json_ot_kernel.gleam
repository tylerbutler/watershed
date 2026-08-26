//// A stateful client-transform kernel over the pure json0 algebra in
//// `json_ot.gleam`. It runs on the central sequencer of watershed. The
//// discipline is the same as in `map_kernel.gleam`. There is no process and
//// there are no side effects. Every operation returns the new state with the
//// events that it produced. The runtime actor owns the sequencing, which is
//// the SN, the RSN, and the FIFO ack matching. The kernel assumes only that
//// the acks arrive in submission order.
////
//// ## One op in flight (the Wave and ShareDB client model)
////
//// floodgate never transforms, because the sequencer does not know the
//// kernels. It broadcasts an op without a change, with the reference sequence
//// number (RSN) that the author wrote it against. A receiver must thus
//// transform that op past every op that sequenced in the window
//// `(op.ref_seq, op.seq)`, because the author did not see those ops.
////
//// For the context to stay consistent, no earlier unacked op of the same
//// author can come before the incoming op in that window. If one does, the
//// context of the incoming op already contains ops that the window replay does
//// not contain. This is the dOPT hazard.
////
//// This kernel prevents that condition. It keeps one op **in flight** at most.
//// `inflight` is the one unacked op on the wire, written against `sequenced`.
//// `buffer` composes every optimistic edit that follows, and the kernel
//// releases it as the next `inflight` only when the current `inflight` is
//// acked. The previous op of a client is always acked before the client sends
//// the next one, so no window contains an op from the same author. It is thus
//// correct to transform an incoming op past *every* logged op in its window.
////
//// `side` comes from the sequence order, not from an identity. The op with
//// the larger sequence number is `Rgt`, and the other op is `Lft`. A pending
//// local op has no sequence number yet, but it always sequences after every
//// op that the kernel processes now, so it is always `Rgt`. Every replica
//// reads one total order, so every replica breaks the same
//// insert-at-the-same-index tie in the same way, and TP1 convergence holds.
//// The module doc of `ot_client` describes why an identity does not work
//// here.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/json_ot.{
  type JsonValue, type Op, type PathKey, type Side, Lft, Rgt,
}
import watershed/ot_client.{LogEntry}

/// A sequenced op that the kernel keeps for the concurrency window. The kernel
/// already transformed it into the context that it was applied in, which is
/// the head context at its `seq`. This is an alias for the shared log-entry
/// shape of `ot_client`, with the `Op` type of json0.
type LogEntry =
  ot_client.LogEntry(Op)

/// The server-confirmed document, the concurrency-window `log`, the one
/// in-flight op, and a composed buffer of the later optimistic edits.
pub type JsonOtState {
  JsonOtState(
    /// The server-confirmed document, with every sequenced op applied in
    /// order.
    sequenced: JsonValue,
    /// The sequenced ops in head context, oldest first. The kernel keeps an op
    /// while a future `(ref_seq, seq)` window can contain it, which is while
    /// `seq > MSN`.
    log: List(LogEntry),
    /// The one unacked op on the wire, expressed against `sequenced`. The
    /// kernel rebases it as the remote ops arrive. The value is `None` when no
    /// op is in flight.
    inflight: Option(Op),
    /// The optimistic edits that the client wrote after it sent `inflight`,
    /// composed into one op that is expressed against `sequenced` ∘
    /// `inflight`. The kernel releases it as the next `inflight` on an ack. The
    /// value is `None` when there is no such edit.
    buffer: Option(Op),
    /// A buffer that an ack released as the new `inflight`, which waits to go
    /// on the wire. `take_outbound` removes it. The runtime cannot send it
    /// immediately, because it processes an ack while it reads a sequenced
    /// message. The value is `None` when there is nothing to send.
    outbound: Option(JsonOtWireOp),
  )
}

/// An op in its wire form: the components with the reference sequence number
/// that the author wrote them against. The receiver needs that number to
/// rebuild its concurrency window. The sequencer envelope supplies `author` and
/// `seq`.
pub type JsonOtWireOp {
  JsonOtWireOp(ref_seq: Int, components: Op)
}

/// The kernel emits this event when the observable document changes. There is
/// one event for each op component.
pub type JsonOtEvent {
  DocChanged(path: List(PathKey), local: Bool)
}

pub type KernelError {
  /// An ack arrived with nothing in flight.
  UnexpectedAck(detail: String)
  /// The pure algebra refused an apply or a transform, for example for a bad
  /// path or a bad value.
  OtFailure(err: json_ot.OtError)
}

// ─────────────────────────────────────────────────────────────────────────────
// Construction / summary round-trip
// ─────────────────────────────────────────────────────────────────────────────

/// A new kernel over an empty object document.
pub fn new() -> JsonOtState {
  from_value(json_ot.VObject([]))
}

/// A new kernel with an initial document value.
pub fn from_value(doc: JsonValue) -> JsonOtState {
  JsonOtState(
    sequenced: doc,
    log: [],
    inflight: None,
    buffer: None,
    outbound: None,
  )
}

/// Load a state that contains sequenced data only, from a stored summary. A
/// summary never contains a local edit, and the concurrency window starts
/// empty.
pub fn from_summary(doc: JsonValue) -> JsonOtState {
  from_value(doc)
}

/// The confirmed document that a summary captures. It contains the sequenced
/// data only, and no local edit.
pub fn summary(state: JsonOtState) -> JsonValue {
  state.sequenced
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

/// The optimistic document: `sequenced` with `inflight` applied, and then
/// `buffer`.
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

/// Apply an op to a document. This is json0 J2 to J4.
pub fn apply_op(doc: JsonValue, op: Op) -> Result(JsonValue, KernelError) {
  json_ot.apply(doc, op) |> result.map_error(OtFailure)
}

/// Transform `a` past `b` for the supplied side. This is json0 J5 to J8, and
/// it holds TP1.
pub fn transform(a: Op, b: Op, side: Side) -> Result(Op, KernelError) {
  json_ot.transform(a, b, side) |> result.map_error(OtFailure)
}

/// Compose two consecutive ops into one, which is json0 J9. The result
/// applies `b` after `a`.
pub fn compose(a: Op, b: Op) -> Op {
  list.append(a, b)
}

/// Invert an op with the pre-images that its `od` and `ld` components already
/// carry.
pub fn invert(op: Op) -> Op {
  json_ot.invert(op)
}

// ─────────────────────────────────────────────────────────────────────────────
// Local operations (optimistic apply + outbound op)
// ─────────────────────────────────────────────────────────────────────────────

/// Write a local edit against the current optimistic view.
///
/// If no op is in flight, the edit becomes `inflight`, and the function returns
/// it as a wire op to send. That op carries `ref_seq`, which is the last
/// sequence number that the client received.
///
/// If an op is in flight, the function composes the edit into `buffer` and
/// holds it until an ack retires the in-flight op. One op is thus on the wire
/// at most. `Ok(#(state, None, events))` means that there is nothing to send
/// yet.
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

/// Apply a sequenced op that another client wrote. `seq` is its sequence
/// number, and `msn` is the minimum sequence number, which the log garbage
/// collection uses.
///
/// The kernel transforms the op into head context past every op that sequenced
/// in `(ref_seq, seq)`. No op in that window can come from the same author,
/// because one op is in flight at most, so the window has no gap. The kernel
/// then applies the op, logs it, and rebases `inflight` and `buffer` past it.
///
/// The incoming op sequenced after every op in its window, so it is `Rgt`
/// there. It sequenced before `inflight` and before `buffer`, which are not
/// sequenced yet, so it is `Lft` against each of them.
pub fn apply_remote(
  state: JsonOtState,
  wire: JsonOtWireOp,
  seq: Int,
  msn: Int,
) -> Result(#(JsonOtState, List(JsonOtEvent)), KernelError) {
  use op_head <- result.try(
    ot_client.to_head_context(
      state.log,
      wire.ref_seq,
      seq,
      wire.components,
      fn(current, e) { transform(current, e.op, Rgt) },
    ),
  )
  use sequenced <- result.try(apply_op(state.sequenced, op_head))
  // Rebase the in-flight op, then the buffer (which lives one context deeper),
  // advancing the remote op past each so the next rebase is well-formed.
  use #(inflight, remote_after_inflight) <- result.try(
    ot_client.rebase_pending(
      state.inflight,
      op_head,
      fn(local, remote) { transform(local, remote, Rgt) },
      fn(remote, local) { transform(remote, local, Lft) },
    ),
  )
  use #(buffer, _remote_after_buffer) <- result.try(
    ot_client.rebase_pending(
      state.buffer,
      remote_after_inflight,
      fn(local, remote) { transform(local, remote, Rgt) },
      fn(remote, local) { transform(remote, local, Lft) },
    ),
  )
  let log =
    ot_client.gc_log(list.append(state.log, [LogEntry(seq, op_head)]), msn)
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

/// Commit the local op after the server sequences it. That op is the current
/// `inflight`, which the kernel already rebased past every concurrent remote
/// op. The kernel thus applies it to `sequenced` and logs it in head context.
///
/// If there is a `buffer`, the kernel releases it as the next `inflight` and
/// puts it in `outbound`, for the runtime to send with `take_outbound`. That op
/// carries `ref_seq = seq`, because the buffer is expressed against `sequenced`
/// with the acked op applied. The optimistic view does not change, so the
/// kernel emits no event.
///
/// The `_wire` value that the sequencer echoes is the original op that the
/// client submitted. The sequencer never transforms, so that value does not
/// equal the rebased in-flight op. The kernel uses it for the FIFO order
/// only.
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
        ot_client.gc_log(list.append(state.log, [LogEntry(seq, inflight)]), msn)
      // Release the buffer as the next in-flight op, if any.
      let #(next_inflight, to_send) =
        ot_client.promote_buffer(state.buffer, seq, JsonOtWireOp)
      let state =
        JsonOtState(
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

/// Take the op that `ack_local` released onto the wire, which is a buffer that
/// became the new in-flight op. The function returns the op to send and empties
/// the pending slot. The result is `None` when there is no such op. A second
/// call has no more effect.
pub fn take_outbound(
  state: JsonOtState,
) -> #(JsonOtState, Option(JsonOtWireOp)) {
  let #(outbound, taken) = ot_client.take_pending(state.outbound)
  #(JsonOtState(..state, outbound: outbound), taken)
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

fn events_for(op: Op, local: Bool) -> List(JsonOtEvent) {
  list.map(op, fn(component) { DocChanged(component.path, local) })
}
