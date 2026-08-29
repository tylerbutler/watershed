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
//// The `pending` field holds that op, which is written against `sequenced`.
//// The same field composes every optimistic edit that follows into one
//// buffer, and the kernel releases that buffer onto the wire only when the
//// server acks the op that is already there. The previous op of a client is
//// always acked before the client sends the next one, so no window contains an
//// op from the same author. It is thus correct to transform an incoming op
//// past *every* logged op in its window.
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
import gleam/option.{type Option, None}
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

/// The server-confirmed document, the concurrency-window `log`, and the
/// unacknowledged local edits.
pub type JsonOtState {
  JsonOtState(
    /// The server-confirmed document, with every sequenced op applied in
    /// order.
    sequenced: JsonValue,
    /// The sequenced ops in head context, oldest first. The kernel keeps an op
    /// while a future `(ref_seq, seq)` window can contain it, which is while
    /// `seq > MSN`.
    log: List(LogEntry),
    /// The unacknowledged local edits. `ot_client.InFlight` holds the one op
    /// on the wire, which the kernel rebases as the remote ops arrive.
    /// `ot_client.InFlightAndBuffered` also holds the optimistic edits that
    /// the client wrote after it sent that op, composed into one op. The
    /// kernel releases the buffer as the next op on the wire on an ack.
    pending: ot_client.Pending(Op),
    /// A buffer that an ack released onto the wire, which waits to be sent.
    /// `take_outbound` removes it. The runtime cannot send it
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
  OtFailure(error: json_ot.OtError)
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
  JsonOtState(sequenced: doc, log: [], pending: ot_client.Idle, outbound: None)
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

/// The optimistic document: `sequenced` with the op on the wire applied, and
/// then the buffered edits.
pub fn view(state: JsonOtState) -> Result(JsonValue, KernelError) {
  case state.pending {
    ot_client.Idle -> Ok(state.sequenced)
    ot_client.InFlight(op) -> apply_op(state.sequenced, op)
    ot_client.InFlightAndBuffered(op, buffered) -> {
      use after_op <- result.try(apply_op(state.sequenced, op))
      apply_op(after_op, buffered)
    }
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
/// If no op is in flight, the edit goes on the wire, and the function returns
/// it as a wire op to send. That op carries `ref_seq`, which is the last
/// sequence number that the client received.
///
/// If an op is in flight, the function composes the edit into the buffer and
/// holds it until an ack retires the op on the wire. One op is thus on the wire
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
  use #(pending, to_send) <- result.try(
    ot_client.hold_local(state.pending, components, fn(buffered, edit) {
      Ok(compose(buffered, edit))
    }),
  )
  Ok(#(
    JsonOtState(..state, pending: pending),
    option.map(to_send, JsonOtWireOp(ref_seq, _)),
    events_for(components, True),
  ))
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
/// then applies the op, logs it, and rebases every unacknowledged local edit
/// past it.
///
/// The incoming op sequenced after every op in its window, so it is `Rgt`
/// there. It sequenced before the op on the wire and before the buffer, which
/// are not sequenced yet, so it is `Lft` against each of them.
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
  use #(pending, _remote_after_pending) <- result.try(
    ot_client.rebase_pending(
      state.pending,
      op_head,
      fn(local, remote) { transform(local, remote, Rgt) },
      fn(remote, local) { transform(remote, local, Lft) },
    ),
  )
  let log =
    ot_client.gc_log(list.append(state.log, [LogEntry(seq, op_head)]), msn)
  let state =
    JsonOtState(..state, sequenced: sequenced, log: log, pending: pending)
  Ok(#(state, events_for(op_head, False)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Acks (own ops coming back sequenced)
// ─────────────────────────────────────────────────────────────────────────────

/// Commit the local op after the server sequences it. That op is the current op
/// on the wire, which the kernel already rebased past every concurrent remote
/// op. The kernel thus applies it to `sequenced` and logs it in head context.
///
/// If there is a buffer, the kernel releases it as the next op on the wire and
/// puts it in `outbound`, for the runtime to send with `take_outbound`. That op
/// carries `ref_seq = seq`, because the buffer is expressed against `sequenced`
/// with the acked op applied. The optimistic view does not change, so the
/// kernel emits no event.
///
/// The `_wire` value that the sequencer echoes is the original op that the
/// client submitted. The sequencer never transforms, so that value does not
/// equal the rebased op on the wire. The kernel uses it for the FIFO order
/// only.
pub fn ack_local(
  state: JsonOtState,
  _wire: JsonOtWireOp,
  seq: Int,
  msn: Int,
) -> Result(#(JsonOtState, List(JsonOtEvent)), KernelError) {
  use in_flight <- result.try(
    ot_client.in_flight(state.pending)
    |> result.replace_error(UnexpectedAck("ack with nothing in flight")),
  )
  use sequenced <- result.try(apply_op(state.sequenced, in_flight))
  let log =
    ot_client.gc_log(list.append(state.log, [LogEntry(seq, in_flight)]), msn)
  // Release the buffer as the next op on the wire, if there is one.
  let #(pending, to_send) =
    ot_client.promote_buffer(state.pending, seq, JsonOtWireOp)
  let state =
    JsonOtState(
      sequenced: sequenced,
      log: log,
      pending: pending,
      outbound: to_send,
    )
  Ok(#(state, []))
}

/// Take the op that `ack_local` released onto the wire, which is a buffer that
/// became the new op on the wire. The function returns the op to send and empties
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
