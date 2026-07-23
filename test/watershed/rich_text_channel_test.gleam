//// SharedRichText ↔ channel/wire wiring tests: the OT client-transform
//// kernel driven through `channel` and `wire/ops`. Kernel-internal
//// client-transform semantics are covered by `rich_text_kernel_test`/
//// `rich_text_kernel_converge_test`; these pin the *wiring*: channel type
//// dispatch, op/snapshot wire shape and round trip, malformed-op rejection,
//// `same_shape`/`same_snapshot`, attach-vs-persisted snapshot semantics,
//// `apply_remote`/`ack_local`/`take_outbound` dispatch, and handle discovery
//// through embeds and attributes.
////
//// No runtime edit API exists yet for RichText (out of scope for this
//// task), so these tests drive `rich_text_kernel` directly and dispatch
//// through `channel`/`wire/ops`, mirroring how `pact_map_channel_test`
//// exercises `channel.apply_remote` without going through `runtime_core`'s
//// per-kernel edit verbs.

import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import startest/expect

import watershed/channel
import watershed/handle
import watershed/json_ot
import watershed/rich_text
import watershed/rich_text_kernel
import watershed/wire
import watershed/wire/ops

fn document(raw: String) -> rich_text.Document {
  let assert Ok(document) = rich_text.document_from_json_string(raw)
  document
}

fn delta(raw: String) -> rich_text.Delta {
  let assert Ok(delta) = rich_text.delta_from_json_string(raw)
  delta
}

fn meta(
  seq seq: Int,
  min_seq min_seq: Int,
  author author: Int,
  self_id self_id: Int,
) -> channel.SequencedMeta {
  channel.SequencedMeta(
    seq: seq,
    last_seen_sn: seq - 1,
    min_seq: min_seq,
    author: author,
    self: self_id,
    quorum: [author, self_id],
    reference_sequence_number: 0,
  )
}

// ── channel type dispatch ────────────────────────────────────────────────────

pub fn rich_text_channel_type_round_trips_test() {
  channel.type_to_string(channel.RichTextChannel)
  |> expect.to_equal(wire.channel_type_rich_text)
  channel.type_to_string(channel.RichTextChannel)
  |> channel.type_from_string
  |> expect.to_equal(Ok(channel.RichTextChannel))
}

pub fn rich_text_init_type_and_new_dispatch_test() {
  channel.init_type(channel.InitRichText) |> expect.to_equal(channel.RichTextChannel)

  let state = channel.new(channel.InitRichText, replica: "client-a")
  channel.channel_type(state) |> expect.to_equal(channel.RichTextChannel)
  channel.snapshot(state)
  |> expect.to_equal(channel.RichTextSnapshot(rich_text.empty_document()))
}

pub fn rich_text_snapshot_type_dispatch_test() {
  let snapshot = channel.RichTextSnapshot(rich_text.empty_document())
  channel.snapshot_type(snapshot) |> expect.to_equal(channel.RichTextChannel)
}

// ── op wire shape and round trip ────────────────────────────────────────────

pub fn rich_text_op_json_exact_shape_test() {
  let op = rich_text_kernel.RichTextWireOp(12, delta("[{\"insert\":\"hi\"}]"))
  ops.encode_rich_text_op(op)
  |> json.to_string
  |> expect.to_equal("{\"refSeq\":12,\"delta\":[{\"insert\":\"hi\"}]}")
}

pub fn rich_text_op_round_trips_through_channel_envelope_test() {
  let op =
    rich_text_kernel.RichTextWireOp(
      3,
      delta("[{\"retain\":2},{\"insert\":\"X\",\"attributes\":{\"bold\":true}}]"),
    )
  let encoded =
    ops.encode_channel_envelope("doc-1", channel.RichTextOp(op))
    |> json.to_string
  let assert Ok(dynamic_value) = json.parse(encoded, decode.dynamic)
  let assert Ok(ops.ChannelOp("doc-1", payload)) =
    ops.decode_op_contents(dynamic_value)
  let assert Ok(channel.RichTextOp(decoded)) =
    decode.run(payload, ops.channel_op_decoder(channel.RichTextChannel))
  decoded |> expect.to_equal(op)
}

pub fn rich_text_op_decoder_rejects_non_array_delta_test() {
  let assert Ok(dynamic_value) =
    json.parse(
      "{\"refSeq\":0,\"delta\":\"not-an-array\"}",
      decode.dynamic,
    )
  let _ =
    decode.run(dynamic_value, ops.rich_text_op_decoder())
    |> expect.to_be_error()
  Nil
}

pub fn rich_text_op_decoder_rejects_malformed_operation_test() {
  let assert Ok(dynamic_value) =
    json.parse(
      "{\"refSeq\":0,\"delta\":[{\"insert\":\"x\",\"delete\":1}]}",
      decode.dynamic,
    )
  let _ =
    decode.run(dynamic_value, ops.rich_text_op_decoder())
    |> expect.to_be_error()
  Nil
}

pub fn rich_text_op_decoder_rejects_missing_ref_seq_test() {
  let assert Ok(dynamic_value) =
    json.parse("{\"delta\":[{\"insert\":\"x\"}]}", decode.dynamic)
  let _ =
    decode.run(dynamic_value, ops.rich_text_op_decoder())
    |> expect.to_be_error()
  Nil
}

// ── snapshot wire shape and round trip ──────────────────────────────────────

pub fn rich_text_snapshot_json_exact_shape_test() {
  let snapshot =
    channel.RichTextSnapshot(document(
      "[{\"insert\":\"hi\",\"attributes\":{\"bold\":true}}]",
    ))
  channel.encode_snapshot(snapshot)
  |> json.to_string
  |> expect.to_equal("[{\"insert\":\"hi\",\"attributes\":{\"bold\":true}}]")
}

pub fn rich_text_snapshot_round_trips_test() {
  let snapshot = channel.RichTextSnapshot(document("[{\"insert\":\"ABC\"}]"))
  let encoded = channel.encode_snapshot(snapshot)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.RichTextChannel),
    )

  channel.same_snapshot(snapshot, decoded) |> expect.to_be_true()
}

pub fn rich_text_snapshot_decoder_rejects_non_insert_only_operations_test() {
  let _ =
    json.parse(
      "[{\"delete\":1}]",
      channel.snapshot_decoder(channel.RichTextChannel),
    )
    |> expect.to_be_error()
  Nil
}

// ── attach vs. persisted snapshot ───────────────────────────────────────────

pub fn rich_text_attach_snapshot_includes_pending_persisted_excludes_it_test() {
  let kernel = rich_text_kernel.new(0)
  let a = delta("[{\"insert\":\"A\"}]")
  let assert Ok(#(kernel, _, _)) = rich_text_kernel.submit(kernel, a, 0)
  let state = channel.RichTextState(kernel)

  channel.snapshot(state)
  |> expect.to_equal(channel.RichTextSnapshot(rich_text.empty_document()))
  channel.attach_snapshot(state)
  |> expect.to_equal(channel.RichTextSnapshot(document("[{\"insert\":\"A\"}]")))
}

pub fn rich_text_attach_state_reconstructs_from_snapshot_test() {
  let kernel = rich_text_kernel.new(0)
  let a = delta("[{\"insert\":\"A\"}]")
  let assert Ok(#(kernel, _, _)) = rich_text_kernel.submit(kernel, a, 0)
  let state = channel.RichTextState(kernel)

  let attached = channel.attach_state(state, replica: "client-b")
  let assert channel.RichTextState(attached_kernel) = attached
  rich_text_kernel.view(attached_kernel)
  |> expect.to_equal(Ok(document("[{\"insert\":\"A\"}]")))
  rich_text_kernel.summary(attached_kernel)
  |> expect.to_equal(document("[{\"insert\":\"A\"}]"))
}

// ── same_shape / same_snapshot ───────────────────────────────────────────────

pub fn rich_text_same_shape_requires_ref_seq_and_delta_equality_test() {
  let op = rich_text_kernel.RichTextWireOp(1, delta("[{\"insert\":\"A\"}]"))
  let same_op =
    rich_text_kernel.RichTextWireOp(1, delta("[{\"insert\":\"A\"}]"))
  channel.same_shape(channel.RichTextOp(op), channel.RichTextOp(same_op))
  |> expect.to_be_true()

  let different_ref_seq =
    rich_text_kernel.RichTextWireOp(2, delta("[{\"insert\":\"A\"}]"))
  channel.same_shape(channel.RichTextOp(op), channel.RichTextOp(different_ref_seq))
  |> expect.to_be_false()

  let different_delta =
    rich_text_kernel.RichTextWireOp(1, delta("[{\"insert\":\"B\"}]"))
  channel.same_shape(channel.RichTextOp(op), channel.RichTextOp(different_delta))
  |> expect.to_be_false()
}

pub fn rich_text_same_snapshot_requires_canonical_document_equality_test() {
  let ours = channel.RichTextSnapshot(document("[{\"insert\":\"AB\"}]"))
  let same = channel.RichTextSnapshot(document("[{\"insert\":\"AB\"}]"))
  channel.same_snapshot(ours, same) |> expect.to_be_true()

  let different = channel.RichTextSnapshot(document("[{\"insert\":\"AC\"}]"))
  channel.same_snapshot(ours, different) |> expect.to_be_false()
}

// ── apply_remote / ack_local / take_outbound dispatch ───────────────────────

pub fn rich_text_apply_remote_dispatch_test() {
  let state = channel.RichTextState(rich_text_kernel.new(1))
  let op = channel.RichTextOp(rich_text_kernel.RichTextWireOp(0, delta(
    "[{\"insert\":\"X\"}]",
  )))

  let assert Ok(#(state, events, owed)) =
    channel.apply_remote(state, op, meta(seq: 1, min_seq: 1, author: 0, self_id: 1))
  owed |> expect.to_equal([])
  let assert channel.RichTextState(kernel) = state
  rich_text_kernel.summary(kernel)
  |> expect.to_equal(document("[{\"insert\":\"X\"}]"))
  events
  |> expect.to_equal([
    channel.RichTextEvent(rich_text_kernel.RichTextChanged(
      delta("[{\"insert\":\"X\"}]"),
      False,
    )),
  ])
}

pub fn rich_text_ack_local_dispatch_uses_no_meta_test() {
  let kernel = rich_text_kernel.new(0)
  let a = delta("[{\"insert\":\"A\"}]")
  let assert Ok(#(kernel, Some(wire_op), _)) =
    rich_text_kernel.submit(kernel, a, 0)
  let state = channel.RichTextState(kernel)

  let assert Ok(#(state, events, resolution)) =
    channel.ack_local(
      state,
      channel.RichTextOp(wire_op),
      channel.NoMeta,
      meta(seq: 1, min_seq: -1, author: 0, self_id: 0),
    )
  events |> expect.to_equal([])
  resolution |> expect.to_equal(None)
  let assert channel.RichTextState(kernel) = state
  rich_text_kernel.summary(kernel) |> expect.to_equal(document(
    "[{\"insert\":\"A\"}]",
  ))
}

pub fn rich_text_take_outbound_drains_buffered_op_test() {
  let kernel = rich_text_kernel.new(0)
  let a = delta("[{\"insert\":\"A\"}]")
  let b = delta("[{\"retain\":1},{\"insert\":\"B\"}]")
  let assert Ok(#(kernel, Some(wire_a), _)) =
    rich_text_kernel.submit(kernel, a, 0)
  let assert Ok(#(kernel, _, _)) = rich_text_kernel.submit(kernel, b, 0)
  let state = channel.RichTextState(kernel)

  let assert Ok(#(state, _, _)) =
    channel.ack_local(
      state,
      channel.RichTextOp(wire_a),
      channel.NoMeta,
      meta(seq: 1, min_seq: -1, author: 0, self_id: 0),
    )

  let #(state, outbound) = channel.take_outbound(state)
  outbound |> expect.to_equal(Some(channel.RichTextOp(
    rich_text_kernel.RichTextWireOp(1, b),
  )))
  let #(_, again) = channel.take_outbound(state)
  again |> expect.to_equal(None)
}

pub fn rich_text_wrong_channel_type_errors_test() {
  let state = channel.new(channel.InitMap, replica: "client-a")
  let op =
    channel.RichTextOp(rich_text_kernel.RichTextWireOp(
      0,
      delta("[{\"insert\":\"A\"}]"),
    ))
  let _ =
    channel.apply_remote(state, op, meta(seq: 1, min_seq: -1, author: 0, self_id: 1))
    |> expect.to_be_error()
  Nil
}

// ── handle discovery ─────────────────────────────────────────────────────────

fn handle_value(address: String) -> json_ot.JsonValue {
  let assert Ok(value) =
    json_ot.from_json_string(json.to_string(handle.encode_handle(address)))
  value
}

pub fn rich_text_discovers_handles_in_embeds_and_attributes_test() {
  let assert Ok(document) =
    rich_text.empty_document()
    |> rich_text.document_insert_embed(
      handle_value("embed-child"),
      rich_text.attributes([]),
    )
  let assert Ok(document) =
    document
    |> rich_text.document_insert_text(
      "hi",
      rich_text.attributes([#("link", handle_value("attr-child"))]),
    )
  let kernel = rich_text_kernel.from_document(0, document)

  channel.handle_addresses(channel.RichTextState(kernel))
  |> expect.to_equal(["embed-child", "attr-child"])
}
