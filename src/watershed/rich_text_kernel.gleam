//// Stateful client-transform kernel over the checked rich-text Delta algebra.
////
//// The central sequencer broadcasts the operations without a change. This
//// kernel keeps one local operation in flight at most, and it composes the
//// later edits into one buffer. The kernel can thus transform every received
//// operation through a complete concurrency window.
////
//// The transform side comes from the sequence order, and not from an
//// identity. rich-text reverses the side convention of json0, so the
//// operation with the larger sequence number is `Left`, and the other
//// operation is `Right`. An insert of the operation that sequenced first thus
//// comes first. A pending local operation always sequences after every
//// operation that the kernel processes now, so it is always `Left`. The
//// module doc of `ot_client` describes why an identity does not work here.

import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import watershed/ot_client
import watershed/rich_text

pub type RichTextState {
  RichTextState(
    /// The server-confirmed document.
    sequenced: rich_text.Document,
    /// The sequenced operations that a concurrency window can still contain.
    log: List(ot_client.LogEntry(rich_text.Delta)),
    /// The unacknowledged local edits. The type holds the one operation on the
    /// wire, and the composed buffer of the later edits behind it.
    pending: ot_client.Pending(rich_text.Delta),
    /// An operation that an acknowledgement released onto the wire, which waits
    /// to be sent. `take_outbound` removes it.
    outbound: Option(RichTextWireOperation),
  )
}

pub type RichTextWireOperation {
  RichTextWireOperation(ref_seq: Int, delta: rich_text.Delta)
}

pub type RichTextEvent {
  RichTextChanged(delta: rich_text.Delta, local: Bool)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  RichTextFailure(error: rich_text.Error)
}

/// Start with an empty rich-text document.
pub fn new() -> RichTextState {
  from_document(rich_text.empty_document())
}

/// Start from a confirmed initial document.
pub fn from_document(document: rich_text.Document) -> RichTextState {
  RichTextState(
    sequenced: document,
    log: [],
    pending: ot_client.Idle,
    outbound: None,
  )
}

/// Restore a sequenced-only summary.
pub fn from_summary(document: rich_text.Document) -> RichTextState {
  from_document(document)
}

/// A summary never includes optimistic local edits.
pub fn summary(state: RichTextState) -> rich_text.Document {
  state.sequenced
}

/// The optimistic document. This is the confirmed state with the pending
/// local edits after it.
pub fn view(state: RichTextState) -> Result(rich_text.Document, KernelError) {
  case state.pending {
    ot_client.Idle -> Ok(state.sequenced)
    ot_client.InFlight(delta) -> apply_operation(state.sequenced, delta)
    ot_client.InFlightAndBuffered(delta, buffered) -> {
      use after_delta <- result.try(apply_operation(state.sequenced, delta))
      apply_operation(after_delta, buffered)
    }
  }
}

pub fn apply_operation(
  document: rich_text.Document,
  delta: rich_text.Delta,
) -> Result(rich_text.Document, KernelError) {
  rich_text.apply(document, delta) |> result.map_error(RichTextFailure)
}

pub fn transform(
  a: rich_text.Delta,
  b: rich_text.Delta,
  side: rich_text.Side,
) -> Result(rich_text.Delta, KernelError) {
  rich_text.transform(a, b, side) |> result.map_error(RichTextFailure)
}

pub fn compose(
  a: rich_text.Delta,
  b: rich_text.Delta,
) -> Result(rich_text.Delta, KernelError) {
  rich_text.compose(a, b) |> result.map_error(RichTextFailure)
}

pub fn invert(
  delta: rich_text.Delta,
  base: rich_text.Document,
) -> Result(rich_text.Delta, KernelError) {
  rich_text.invert(delta, base) |> result.map_error(RichTextFailure)
}

/// Apply a local edit optimistically. The kernel releases only the first
/// pending edit to the caller. It composes each later edit into the one
/// buffer.
pub fn submit(
  state: RichTextState,
  delta: rich_text.Delta,
  ref_seq: Int,
) -> Result(
  #(RichTextState, Option(RichTextWireOperation), List(RichTextEvent)),
  KernelError,
) {
  use delta <- result.try(
    rich_text.delta_operations(delta)
    |> result.map_error(RichTextFailure),
  )
  use current <- result.try(view(state))
  use _ <- result.try(apply_operation(current, delta))
  let events = [RichTextChanged(delta, True)]
  use #(pending, to_send) <- result.try(ot_client.hold_local(
    state.pending,
    delta,
    compose,
  ))
  Ok(#(
    RichTextState(..state, pending: pending),
    option.map(to_send, RichTextWireOperation(ref_seq, _)),
    events,
  ))
}

/// Integrate a sequenced operation from another author. The kernel advances
/// the emitted delta through every pending local layer. That delta is thus the
/// exact change to the optimistic editor view, and not only the change to the
/// confirmed document.
pub fn apply_remote(
  state: RichTextState,
  wire: RichTextWireOperation,
  seq: Int,
  msn: Int,
) -> Result(#(RichTextState, List(RichTextEvent)), KernelError) {
  use head_delta <- result.try(
    ot_client.to_head_context(
      state.log,
      wire.ref_seq,
      seq,
      wire.delta,
      fn(current, entry) { transform(current, entry.operation, rich_text.Left) },
    ),
  )
  use sequenced <- result.try(apply_operation(state.sequenced, head_delta))
  use #(pending, remote_after_pending) <- result.try(
    ot_client.rebase_pending(
      state.pending,
      head_delta,
      fn(local, remote) { transform(local, remote, rich_text.Left) },
      fn(remote, local) { transform(remote, local, rich_text.Right) },
    ),
  )
  let log =
    ot_client.gc_log(
      list.append(state.log, [ot_client.LogEntry(seq, head_delta)]),
      msn,
    )
  let state =
    RichTextState(..state, sequenced: sequenced, log: log, pending: pending)
  Ok(#(state, [RichTextChanged(remote_after_pending, False)]))
}

/// Commit the operation on the wire, which the kernel can have rebased. The
/// function ignores the echoed body on purpose, because the FIFO order of the
/// acknowledgement identifies the operation.
pub fn ack_local(
  state: RichTextState,
  _echoed_wire: RichTextWireOperation,
  seq: Int,
  msn: Int,
) -> Result(#(RichTextState, List(RichTextEvent)), KernelError) {
  use in_flight <- result.try(
    ot_client.in_flight(state.pending)
    |> result.replace_error(UnexpectedAck("ack with nothing in flight")),
  )
  use sequenced <- result.try(apply_operation(state.sequenced, in_flight))
  let log =
    ot_client.gc_log(
      list.append(state.log, [ot_client.LogEntry(seq, in_flight)]),
      msn,
    )
  let #(pending, outbound) =
    ot_client.promote_buffer(state.pending, seq, RichTextWireOperation)
  Ok(
    #(
      RichTextState(
        sequenced: sequenced,
        log: log,
        pending: pending,
        outbound: outbound,
      ),
      [],
    ),
  )
}

/// Take the operation that an acknowledgement released. After that, each
/// further call gives `None`.
pub fn take_outbound(
  state: RichTextState,
) -> #(RichTextState, Option(RichTextWireOperation)) {
  let #(outbound, taken) = ot_client.take_pending(state.outbound)
  #(RichTextState(..state, outbound: outbound), taken)
}
