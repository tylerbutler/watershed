import gleam/option.{None, Some}
import startest/expect
import watershed/ot_client
import watershed/rich_text
import watershed/rich_text_kernel.{RichTextChanged, RichTextWireOperation} as kernel

fn document(raw: String) -> rich_text.Document {
  let assert Ok(document) = rich_text.parse_document(raw)
  document
}

fn delta(raw: String) -> rich_text.Delta {
  let assert Ok(delta) = rich_text.parse_delta(raw)
  delta
}

pub fn new_summary_and_view_test() -> Nil {
  let state = kernel.new()
  state.sequenced |> expect.to_equal(rich_text.empty_document())
  kernel.summary(state) |> expect.to_equal(rich_text.empty_document())
  kernel.view(state) |> expect.to_equal(Ok(rich_text.empty_document()))

  let base = document("[{\"insert\":\"A😀\"}]")
  kernel.from_document(base).sequenced |> expect.to_equal(base)
  let from_summary = kernel.from_summary(base)
  kernel.summary(from_summary) |> expect.to_equal(base)
  kernel.view(from_summary) |> expect.to_equal(Ok(base))
}

pub fn immediate_and_buffered_submit_have_optimistic_view_test() -> Nil {
  let a = delta("[{\"insert\":\"A\"}]")
  let b = delta("[{\"retain\":1},{\"insert\":\"B\"}]")
  let c = delta("[{\"retain\":2},{\"insert\":\"C\"}]")
  let state = kernel.new()

  let assert Ok(#(state, wire_a, events_a)) = kernel.submit(state, a, 0)
  wire_a |> expect.to_equal(Some(RichTextWireOperation(0, a)))
  events_a |> expect.to_equal([RichTextChanged(a, True)])

  let assert Ok(#(state, wire_b, events_b)) = kernel.submit(state, b, 0)
  wire_b |> expect.to_equal(None)
  events_b |> expect.to_equal([RichTextChanged(b, True)])
  let assert Ok(#(state, wire_c, _)) = kernel.submit(state, c, 0)
  wire_c |> expect.to_equal(None)
  ot_client.buffered(state.pending)
  |> expect.to_equal(Ok(delta("[{\"retain\":1},{\"insert\":\"BC\"}]")))
  kernel.view(state)
  |> expect.to_equal(Ok(document("[{\"insert\":\"ABC\"}]")))
  kernel.summary(state) |> expect.to_equal(rich_text.empty_document())
}

pub fn ack_commits_and_releases_buffer_once_test() -> Nil {
  let a = delta("[{\"insert\":\"A\"}]")
  let b = delta("[{\"retain\":1},{\"insert\":\"B\"}]")
  let state = kernel.new()
  let assert Ok(#(state, _, _)) = kernel.submit(state, a, 0)
  let assert Ok(#(state, _, _)) = kernel.submit(state, b, 0)
  let assert Ok(#(state, events)) =
    kernel.ack_local(
      state,
      RichTextWireOperation(999, delta("[{\"insert\":\"ignored\"}]")),
      1,
      -1,
    )

  events |> expect.to_equal([])
  state.sequenced |> expect.to_equal(document("[{\"insert\":\"A\"}]"))
  ot_client.in_flight(state.pending) |> expect.to_equal(Ok(b))
  ot_client.buffered(state.pending) |> expect.to_equal(Error(Nil))
  let #(state, outbound) = kernel.take_outbound(state)
  outbound |> expect.to_equal(Some(RichTextWireOperation(1, b)))
  let #(state, again) = kernel.take_outbound(state)
  again |> expect.to_equal(None)
  kernel.view(state) |> expect.to_equal(Ok(document("[{\"insert\":\"AB\"}]")))
}

pub fn unexpected_ack_is_rejected_test() -> Nil {
  let unexpected = RichTextWireOperation(0, delta("[{\"insert\":\"A\"}]"))
  kernel.ack_local(kernel.new(), unexpected, 1, -1)
  |> expect.to_equal(Error(kernel.UnexpectedAck("ack with nothing in flight")))
}

pub fn submit_validates_utf16_boundaries_test() -> Nil {
  let state = kernel.from_document(document("[{\"insert\":\"A😀B\"}]"))
  let split_emoji = delta("[{\"retain\":2},{\"delete\":1}]")

  kernel.submit(state, split_emoji, 0)
  |> expect.to_equal(
    Error(kernel.RichTextFailure(rich_text.InvalidBoundary(2))),
  )
}

pub fn remote_apply_without_pending_and_log_gc_test() -> Nil {
  let x = delta("[{\"insert\":\"X\"}]")
  let state = kernel.new()
  let assert Ok(#(state, events)) =
    kernel.apply_remote(state, RichTextWireOperation(0, x), 1, 1)

  state.sequenced |> expect.to_equal(document("[{\"insert\":\"X\"}]"))
  state.log |> expect.to_equal([])
  events |> expect.to_equal([RichTextChanged(x, False)])
}

pub fn stale_reference_transforms_through_concurrency_window_test() -> Nil {
  let a = delta("[{\"insert\":\"A\"}]")
  let b = delta("[{\"insert\":\"B\"}]")
  let state = kernel.new()
  let assert Ok(#(state, _, _)) = kernel.submit(state, a, 0)
  let assert Ok(#(state, _)) =
    kernel.ack_local(state, RichTextWireOperation(0, a), 1, -1)
  let assert Ok(#(state, _)) =
    kernel.apply_remote(state, RichTextWireOperation(0, b), 2, -1)

  state.sequenced |> expect.to_equal(document("[{\"insert\":\"AB\"}]"))
}

/// A remote operation that sequenced already comes before the pending local
/// layers, so the event that the kernel emits inserts in front of them.
pub fn remote_event_is_delta_against_optimistic_view_test() -> Nil {
  let a = delta("[{\"insert\":\"A\"}]")
  let b = delta("[{\"retain\":1},{\"insert\":\"B\"}]")
  let x = delta("[{\"insert\":\"X\"}]")
  let state = kernel.new()
  let assert Ok(#(state, _, _)) = kernel.submit(state, a, 0)
  let assert Ok(#(state, _, _)) = kernel.submit(state, b, 0)
  let assert Ok(#(state, events)) =
    kernel.apply_remote(state, RichTextWireOperation(0, x), 1, -1)

  events
  |> expect.to_equal([RichTextChanged(delta("[{\"insert\":\"X\"}]"), False)])
  state.sequenced |> expect.to_equal(document("[{\"insert\":\"X\"}]"))
  kernel.view(state) |> expect.to_equal(Ok(document("[{\"insert\":\"XAB\"}]")))
}

/// This exercises both directions of the reversed rich-text side adapter.
/// B is concurrent with A, while C is sequenced between them; swapping the
/// adapter arguments/priority can otherwise pass ordinary non-tied TP1 cases.
///
/// The side comes from the sequence order, so the three inserts land in that
/// order: A at sequence_number 1, C at sequence_number 2, and B at
/// sequence_number 3.
pub fn same_position_inserts_land_in_sequence_order_test() -> Nil {
  let a = delta("[{\"insert\":\"A\"}]")
  let b = delta("[{\"insert\":\"B\"}]")
  let c = delta("[{\"retain\":1},{\"insert\":\"C\"}]")

  let c0 = kernel.new()
  let assert Ok(#(c0, _, _)) = kernel.submit(c0, a, 0)
  let assert Ok(#(c0, _)) =
    kernel.ack_local(c0, RichTextWireOperation(0, a), 1, -1)
  let assert Ok(#(c0, _)) =
    kernel.apply_remote(c0, RichTextWireOperation(1, c), 2, -1)
  let assert Ok(#(c0, _)) =
    kernel.apply_remote(c0, RichTextWireOperation(0, b), 3, -1)

  let c1 = kernel.new()
  let assert Ok(#(c1, _, _)) = kernel.submit(c1, b, 0)
  let assert Ok(#(c1, _)) =
    kernel.apply_remote(c1, RichTextWireOperation(0, a), 1, -1)
  let assert Ok(#(c1, _)) =
    kernel.apply_remote(c1, RichTextWireOperation(1, c), 2, -1)
  let assert Ok(#(c1, _)) =
    kernel.ack_local(c1, RichTextWireOperation(0, b), 3, -1)

  let c2 = kernel.new()
  let assert Ok(#(c2, _)) =
    kernel.apply_remote(c2, RichTextWireOperation(0, a), 1, -1)
  let assert Ok(#(c2, _, _)) = kernel.submit(c2, c, 1)
  let assert Ok(#(c2, _)) =
    kernel.ack_local(c2, RichTextWireOperation(1, c), 2, -1)
  let assert Ok(#(c2, _)) =
    kernel.apply_remote(c2, RichTextWireOperation(0, b), 3, -1)

  let expected = document("[{\"insert\":\"ACB\"}]")
  c0.sequenced |> expect.to_equal(expected)
  c1.sequenced |> expect.to_equal(expected)
  c2.sequenced |> expect.to_equal(expected)
}
