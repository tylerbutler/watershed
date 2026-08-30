//// A stateful client-transform kernel over the pure json0 algebra in
//// `json_ot.gleam`. It runs on the central sequencer of watershed. The
//// discipline is the same as in `map_kernel.gleam`. There is no process and
//// there are no side effects. Every operation returns the new state with the
//// events that it produced. The runtime actor owns the sequencing, which is
//// the SN, the RSN, and the FIFO ack matching. The kernel assumes only that
//// the acks arrive in submission order.
////
//// ## One operation in flight (the Wave and ShareDB client model)
////
//// floodgate never transforms, because the sequencer does not know the
//// kernels. It broadcasts an operation without a change, with the reference
//// sequence number (RSN) that the author wrote it against. A receiver must
//// thus transform that operation past every operation that sequenced in the
//// window `(operation.reference_sequence_number, operation.sequence_number)`,
//// because the author did not see those operations.
////
//// For the context to stay consistent, no earlier unacked operation of the
//// same author can come before the incoming operation in that window. If one
//// does, the context of the incoming operation already contains operations
//// that the window replay does not contain. This is the dOPT hazard.
////
//// This kernel prevents that condition. It keeps one operation **in flight**
//// at most. The `pending` field holds that operation, which is written against
//// `sequenced`. The same field composes every optimistic edit that follows
//// into one buffer, and the kernel releases that buffer onto the wire only
//// when the server acks the operation that is already there. The previous
//// operation of a client is always acked before the client sends the next one,
//// so no window contains an operation from the same author. It is thus correct
//// to transform an incoming operation past *every* logged operation in its
//// window.
////
//// `side` comes from the sequence order, not from an identity. The operation
//// with the larger sequence number is `Rgt`, and the other operation is `Lft`.
//// A pending local operation has no sequence number yet, but it always
//// sequences after every operation that the kernel processes now, so it is
//// always `Rgt`. Every replica reads one total order, so every replica breaks
//// the same insert-at-the-same-index tie in the same way, and TP1 convergence
//// holds. The module doc of `ot_client` describes why an identity does not
//// work here.

import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import watershed/json_ot.{
  type JsonValue, type Operation, type PathKey, type Side, Lft, Rgt,
}
import watershed/ot_client.{LogEntry}

/// A sequenced operation that the kernel keeps for the concurrency window. The
/// kernel already transformed it into the context that it was applied in, which
/// is the head context at its `sequence_number`. This is an alias for the
/// shared log-entry shape of `ot_client`, with the `Operation` type of json0.
type LogEntry =
  ot_client.LogEntry(Operation)

/// The server-confirmed document, the concurrency-window `log`, and the
/// unacknowledged local edits.
pub type JsonOtState {
  JsonOtState(
    /// The server-confirmed document, with every sequenced operation applied in
    /// order.
    sequenced: JsonValue,
    /// The sequenced operations in head context, oldest first. The kernel keeps
    /// an operation while a future `(reference_sequence_number,
    /// sequence_number)` window can contain it, which is while `sequence_number
    /// > MSN`.
    log: List(LogEntry),
    /// The unacknowledged local edits. `ot_client.InFlight` holds the one
    /// operation on the wire, which the kernel rebases as the remote operations
    /// arrive. `ot_client.InFlightAndBuffered` also holds the optimistic edits
    /// that the client wrote after it sent that operation, composed into one
    /// operation. The kernel releases the buffer as the next operation on the
    /// wire on an ack.
    pending: ot_client.Pending(Operation),
    /// A buffer that an ack released onto the wire, which waits to be sent.
    /// `take_outbound` removes it. The runtime cannot send it
    /// immediately, because it processes an ack while it reads a sequenced
    /// message. The value is `None` when there is nothing to send.
    outbound: Option(JsonOtWireOperation),
  )
}

/// An operation in its wire form: the components with the reference sequence
/// number that the author wrote them against. The receiver needs that number to
/// rebuild its concurrency window. The sequencer envelope supplies `author` and
/// `sequence_number`.
pub type JsonOtWireOperation {
  JsonOtWireOperation(reference_sequence_number: Int, components: Operation)
}

/// The kernel emits this event when the observable document changes. There is
/// one event for each operation component.
pub type JsonOtEvent {
  DocumentChanged(path: List(PathKey), local: Bool)
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
pub fn from_value(document: JsonValue) -> JsonOtState {
  JsonOtState(
    sequenced: document,
    log: [],
    pending: ot_client.Idle,
    outbound: None,
  )
}

/// Load a state that contains sequenced data only, from a stored summary. A
/// summary never contains a local edit, and the concurrency window starts
/// empty.
pub fn from_summary(document: JsonValue) -> JsonOtState {
  from_value(document)
}

/// The confirmed document that a summary captures. It contains the sequenced
/// data only, and no local edit.
pub fn summary(state: JsonOtState) -> JsonValue {
  state.sequenced
}

// ─────────────────────────────────────────────────────────────────────────────
// Reads
// ─────────────────────────────────────────────────────────────────────────────

/// The optimistic document: `sequenced` with the operation on the wire applied,
/// and then the buffered edits.
pub fn view(state: JsonOtState) -> Result(JsonValue, KernelError) {
  case state.pending {
    ot_client.Idle -> Ok(state.sequenced)
    ot_client.InFlight(operation) -> apply_operation(state.sequenced, operation)
    ot_client.InFlightAndBuffered(operation, buffered) -> {
      use after_operation <- result.try(apply_operation(
        state.sequenced,
        operation,
      ))
      apply_operation(after_operation, buffered)
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure re-exports (KernelError-wrapped) shared by local + remote paths
// ─────────────────────────────────────────────────────────────────────────────

/// Apply an operation to a document. This is json0 J2 to J4.
pub fn apply_operation(
  document: JsonValue,
  operation: Operation,
) -> Result(JsonValue, KernelError) {
  json_ot.apply(document, operation) |> result.map_error(OtFailure)
}

/// Transform `a` past `b` for the supplied side. This is json0 J5 to J8, and
/// it holds TP1.
pub fn transform(
  a: Operation,
  b: Operation,
  side: Side,
) -> Result(Operation, KernelError) {
  json_ot.transform(a, b, side) |> result.map_error(OtFailure)
}

/// Compose two consecutive operations into one, which is json0 J9. The result
/// applies `b` after `a`.
pub fn compose(a: Operation, b: Operation) -> Operation {
  list.append(a, b)
}

/// Invert an operation with the pre-images that its `od` and `ld` components
/// already carry.
pub fn invert(operation: Operation) -> Operation {
  json_ot.invert(operation)
}

// ─────────────────────────────────────────────────────────────────────────────
// Local operations (optimistic apply + outbound operation)
// ─────────────────────────────────────────────────────────────────────────────

/// Write a local edit against the current optimistic view.
///
/// If no operation is in flight, the edit goes on the wire, and the function
/// returns it as a wire operation to send. That operation carries
/// `reference_sequence_number`, which is the last sequence number that the
/// client received.
///
/// If an operation is in flight, the function composes the edit into the buffer
/// and holds it until an ack retires the operation on the wire. One operation
/// is thus on the wire at most. `Ok(#(state, None, events))` means that there
/// is nothing to send yet.
pub fn submit(
  state: JsonOtState,
  components: Operation,
  reference_sequence_number: Int,
) -> Result(
  #(JsonOtState, Option(JsonOtWireOperation), List(JsonOtEvent)),
  KernelError,
) {
  use current <- result.try(view(state))
  use _ <- result.try(apply_operation(current, components))
  use #(pending, to_send) <- result.try(
    ot_client.hold_local(state.pending, components, fn(buffered, edit) {
      Ok(compose(buffered, edit))
    }),
  )
  Ok(#(
    JsonOtState(..state, pending: pending),
    option.map(to_send, JsonOtWireOperation(reference_sequence_number, _)),
    events_for(components, True),
  ))
}

// ─────────────────────────────────────────────────────────────────────────────
// Remote operations
// ─────────────────────────────────────────────────────────────────────────────

/// Apply a sequenced operation that another client wrote. `sequence_number` is
/// its sequence number, and `minimum_sequence_number` is the minimum sequence
/// number, which the log garbage collection uses.
///
/// The kernel transforms the operation into head context past every operation
/// that sequenced in `(reference_sequence_number, sequence_number)`. No
/// operation in that window can come from the same author, because one
/// operation is in flight at most, so the window has no gap. The kernel then
/// applies the operation, logs it, and rebases every unacknowledged local edit
/// past it.
///
/// The incoming operation sequenced after every operation in its window, so it
/// is `Rgt` there. It sequenced before the operation on the wire and before the
/// buffer, which are not sequenced yet, so it is `Lft` against each of them.
pub fn apply_remote(
  state: JsonOtState,
  wire: JsonOtWireOperation,
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(#(JsonOtState, List(JsonOtEvent)), KernelError) {
  use operation_head <- result.try(
    ot_client.to_head_context(
      state.log,
      wire.reference_sequence_number,
      sequence_number,
      wire.components,
      fn(current, e) { transform(current, e.operation, Rgt) },
    ),
  )
  use sequenced <- result.try(apply_operation(state.sequenced, operation_head))
  use #(pending, _remote_after_pending) <- result.try(
    ot_client.rebase_pending(
      state.pending,
      operation_head,
      fn(local, remote) { transform(local, remote, Rgt) },
      fn(remote, local) { transform(remote, local, Lft) },
    ),
  )
  let log =
    ot_client.gc_log(
      list.append(state.log, [LogEntry(sequence_number, operation_head)]),
      minimum_sequence_number,
    )
  let state =
    JsonOtState(..state, sequenced: sequenced, log: log, pending: pending)
  Ok(#(state, events_for(operation_head, False)))
}

// ─────────────────────────────────────────────────────────────────────────────
// Acks (own operations coming back sequenced)
// ─────────────────────────────────────────────────────────────────────────────

/// Commit the local operation after the server sequences it. That operation is
/// the current operation on the wire, which the kernel already rebased past
/// every concurrent remote operation. The kernel thus applies it to `sequenced`
/// and logs it in head context.
///
/// If there is a buffer, the kernel releases it as the next operation on the
/// wire and puts it in `outbound`, for the runtime to send with
/// `take_outbound`. That operation carries `reference_sequence_number =
/// sequence_number`, because the buffer is expressed against `sequenced` with
/// the acked operation applied. The optimistic view does not change, so the
/// kernel emits no event.
///
/// The `_wire` value that the sequencer echoes is the original operation that
/// the client submitted. The sequencer never transforms, so that value does not
/// equal the rebased operation on the wire. The kernel uses it for the FIFO
/// order only.
pub fn ack_local(
  state: JsonOtState,
  _wire: JsonOtWireOperation,
  sequence_number: Int,
  minimum_sequence_number: Int,
) -> Result(#(JsonOtState, List(JsonOtEvent)), KernelError) {
  use in_flight <- result.try(
    ot_client.in_flight(state.pending)
    |> result.replace_error(UnexpectedAck("ack with nothing in flight")),
  )
  use sequenced <- result.try(apply_operation(state.sequenced, in_flight))
  let log =
    ot_client.gc_log(
      list.append(state.log, [LogEntry(sequence_number, in_flight)]),
      minimum_sequence_number,
    )
  // Release the buffer as the next operation on the wire, if there is one.
  let #(pending, to_send) =
    ot_client.promote_buffer(
      state.pending,
      sequence_number,
      JsonOtWireOperation,
    )
  let state =
    JsonOtState(
      sequenced: sequenced,
      log: log,
      pending: pending,
      outbound: to_send,
    )
  Ok(#(state, []))
}

/// Take the operation that `ack_local` released onto the wire, which is a
/// buffer that became the new operation on the wire. The function returns the
/// operation to send and empties the pending slot. The result is `None` when
/// there is no such operation. A second call has no more effect.
pub fn take_outbound(
  state: JsonOtState,
) -> #(JsonOtState, Option(JsonOtWireOperation)) {
  let #(outbound, taken) = ot_client.take_pending(state.outbound)
  #(JsonOtState(..state, outbound: outbound), taken)
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

fn events_for(operation: Operation, local: Bool) -> List(JsonOtEvent) {
  list.map(operation, fn(component) { DocumentChanged(component.path, local) })
}
