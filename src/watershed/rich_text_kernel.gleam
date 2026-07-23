//// Stateful client-transform kernel over the checked rich-text Delta algebra.
////
//// The central sequencer broadcasts operations unchanged. This kernel keeps at
//// most one local operation in flight, composing later edits into `buffer`, so
//// every received operation can be transformed through a complete concurrency
//// window.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import watershed/ot_client
import watershed/rich_text

pub type RichTextState {
  RichTextState(
    self: Int,
    sequenced: rich_text.Document,
    log: List(ot_client.LogEntry(rich_text.Delta)),
    inflight: Option(rich_text.Delta),
    buffer: Option(rich_text.Delta),
    outbound: Option(RichTextWireOp),
  )
}

pub type RichTextWireOp {
  RichTextWireOp(ref_seq: Int, delta: rich_text.Delta)
}

pub type RichTextEvent {
  RichTextChanged(delta: rich_text.Delta, local: Bool)
}

pub type KernelError {
  UnexpectedAck(detail: String)
  RichTextFailure(error: rich_text.Error)
}

/// Start over an empty rich-text document.
pub fn new(self: Int) -> RichTextState {
  from_document(self, rich_text.empty_document())
}

/// Start from a confirmed initial document.
pub fn from_document(self: Int, document: rich_text.Document) -> RichTextState {
  RichTextState(
    self: self,
    sequenced: document,
    log: [],
    inflight: None,
    buffer: None,
    outbound: None,
  )
}

/// Restore a sequenced-only summary under the supplied client identity.
pub fn from_summary(self: Int, document: rich_text.Document) -> RichTextState {
  from_document(self, document)
}

/// A summary never includes optimistic local edits.
pub fn summary(state: RichTextState) -> rich_text.Document {
  state.sequenced
}

/// The optimistic document: confirmed state followed by pending local edits.
pub fn view(state: RichTextState) -> Result(rich_text.Document, KernelError) {
  use after_inflight <- result.try(apply_optional(
    state.sequenced,
    state.inflight,
  ))
  apply_optional(after_inflight, state.buffer)
}

fn apply_optional(
  document: rich_text.Document,
  maybe_delta: Option(rich_text.Delta),
) -> Result(rich_text.Document, KernelError) {
  case maybe_delta {
    None -> Ok(document)
    Some(delta) -> apply_op(document, delta)
  }
}

pub fn apply_op(
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

/// Optimistically apply a local edit. Only the first pending edit is released
/// to the caller; subsequent edits are composed into the single buffer.
pub fn submit(
  state: RichTextState,
  delta: rich_text.Delta,
  ref_seq: Int,
) -> Result(
  #(RichTextState, Option(RichTextWireOp), List(RichTextEvent)),
  KernelError,
) {
  use delta <- result.try(
    rich_text.delta_operations(delta)
    |> result.map_error(RichTextFailure),
  )
  use current <- result.try(view(state))
  use _ <- result.try(apply_op(current, delta))
  let events = [RichTextChanged(delta, True)]
  case state.inflight {
    None ->
      Ok(#(
        RichTextState(..state, inflight: Some(delta)),
        Some(RichTextWireOp(ref_seq, delta)),
        events,
      ))
    Some(_) -> {
      let buffer_result = case state.buffer {
        None -> Ok(delta)
        Some(buffer) -> compose(buffer, delta)
      }
      use buffer <- result.try(buffer_result)
      Ok(#(RichTextState(..state, buffer: Some(buffer)), None, events))
    }
  }
}

/// Integrate a sequenced operation from another author. The emitted delta is
/// advanced through every pending local layer, making it the exact change to
/// the optimistic editor view rather than merely the confirmed document.
pub fn apply_remote(
  state: RichTextState,
  wire: RichTextWireOp,
  seq: Int,
  author: Int,
  msn: Int,
) -> Result(#(RichTextState, List(RichTextEvent)), KernelError) {
  use head_delta <- result.try(
    ot_client.to_head_context(
      state.log,
      wire.ref_seq,
      seq,
      wire.delta,
      fn(current, entry) {
        transform(current, entry.op, side_of(author, entry.author))
      },
    ),
  )
  use sequenced <- result.try(apply_op(state.sequenced, head_delta))
  use #(inflight, remote_after_inflight) <- result.try(
    ot_client.rebase_pending(
      state.inflight,
      head_delta,
      fn(local, remote) {
        transform(local, remote, side_of(state.self, author))
      },
      fn(remote, local) {
        transform(remote, local, side_of(author, state.self))
      },
    ),
  )
  use #(buffer, remote_after_buffer) <- result.try(
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
      list.append(state.log, [ot_client.LogEntry(seq, author, head_delta)]),
      msn,
    )
  let state =
    RichTextState(
      ..state,
      sequenced: sequenced,
      log: log,
      inflight: inflight,
      buffer: buffer,
    )
  Ok(#(state, [RichTextChanged(remote_after_buffer, False)]))
}

/// Commit the (possibly rebased) in-flight operation. The echoed body is
/// intentionally ignored: FIFO acknowledgement identifies the operation.
pub fn ack_local(
  state: RichTextState,
  _echoed_wire: RichTextWireOp,
  seq: Int,
  msn: Int,
) -> Result(#(RichTextState, List(RichTextEvent)), KernelError) {
  case state.inflight {
    None -> Error(UnexpectedAck("ack with nothing in flight"))
    Some(inflight) -> {
      use sequenced <- result.try(apply_op(state.sequenced, inflight))
      let log =
        ot_client.gc_log(
          list.append(state.log, [ot_client.LogEntry(seq, state.self, inflight)]),
          msn,
        )
      let #(next_inflight, outbound) =
        ot_client.promote_buffer(state.buffer, seq, RichTextWireOp)
      Ok(
        #(
          RichTextState(
            ..state,
            sequenced: sequenced,
            log: log,
            inflight: next_inflight,
            buffer: None,
            outbound: outbound,
          ),
          [],
        ),
      )
    }
  }
}

/// Drain the operation released by an acknowledgement. Once drained, repeated
/// calls yield `None`.
pub fn take_outbound(
  state: RichTextState,
) -> #(RichTextState, Option(RichTextWireOp)) {
  let #(outbound, taken) = ot_client.take_pending(state.outbound)
  #(RichTextState(..state, outbound: outbound), taken)
}

/// rich-text reverses json0's transform-side convention. Lower-numbered
/// authors must therefore use `Right` when transformed past higher authors.
fn side_of(author_x: Int, author_y: Int) -> rich_text.Side {
  case ot_client.author_precedes(author_x, author_y) {
    True -> rich_text.Right
    False -> rich_text.Left
  }
}
