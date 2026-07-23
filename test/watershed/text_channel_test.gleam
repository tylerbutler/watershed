import gleam/json
import gleam/option.{None, Some}
import lattice_core/replica_id
import startest/expect
import watershed/channel
import watershed/counter_kernel
import watershed/text_kernel

fn new_a() -> text_kernel.TextState {
  text_kernel.new(replica_id.new("a"))
}

fn must_insert(
  state: text_kernel.TextState,
  index: Int,
  value: String,
) -> #(text_kernel.TextState, text_kernel.TextOp, Int) {
  let assert Ok(#(state, _events, Some(text_kernel.Submission(op, message_id)))) =
    text_kernel.insert(state, index, value)
  #(state, op, message_id)
}

fn must_delete_range(
  state: text_kernel.TextState,
  start: Int,
  end: Int,
) -> #(text_kernel.TextState, text_kernel.TextOp, Int) {
  let assert Ok(#(state, _events, Some(text_kernel.Submission(op, message_id)))) =
    text_kernel.delete_range(state, start, end)
  #(state, op, message_id)
}

fn must_replace_range(
  state: text_kernel.TextState,
  start: Int,
  end: Int,
  value: String,
) -> #(text_kernel.TextState, text_kernel.TextOp, Int) {
  let assert Ok(#(state, _events, Some(text_kernel.Submission(op, message_id)))) =
    text_kernel.replace_range(state, start, end, value)
  #(state, op, message_id)
}

fn must_append(
  state: text_kernel.TextState,
  value: String,
) -> #(text_kernel.TextState, text_kernel.TextOp, Int) {
  let assert #(state, _events, Some(text_kernel.Submission(op, message_id))) =
    text_kernel.append(state, value)
  #(state, op, message_id)
}

/// A CRDT delta that never legitimately matches a real op's delta: an empty
/// text authored by a replica no honest client would use. Standing in for a
/// tampered/corrupted server echo, mirroring `same_sequence_delta`'s use of
/// `sequence.new(replica_id.new("attacker"))` in the sequence channel tests.
fn tampered_delta() {
  text_kernel.new(replica_id.new("attacker")).sequenced
}

fn no_op_meta() -> channel.SequencedMeta {
  channel.SequencedMeta(
    seq: 1,
    last_seen_sn: 0,
    min_seq: 0,
    author: 1,
    self: 1,
    quorum: [1],
    reference_sequence_number: 0,
  )
}

pub fn text_channel_construction_reports_text_type_test() {
  let state = channel.new(channel.InitText, replica: "a")
  channel.channel_type(state) |> expect.to_equal(channel.TextChannel)
  channel.init_type(channel.InitText) |> expect.to_equal(channel.TextChannel)
  channel.type_to_string(channel.TextChannel) |> expect.to_equal("text")
  channel.type_from_string("text") |> expect.to_equal(Ok(channel.TextChannel))

  let assert channel.TextState(kernel) = state
  text_kernel.value(kernel) |> expect.to_equal("")
}

pub fn text_summary_round_trips_test() {
  let #(state, op, _) = must_insert(new_a(), 0, "hi 👋")
  let assert Ok(state) = text_kernel.ack_local(state, op)
  let summary = channel.TextSummary(state.sequenced)
  channel.snapshot_type(summary) |> expect.to_equal(channel.TextChannel)

  let encoded = channel.encode_snapshot(summary)
  let assert Ok(decoded) =
    json.parse(
      json.to_string(encoded),
      channel.snapshot_decoder(channel.TextChannel),
    )

  channel.same_snapshot(summary, decoded) |> expect.to_be_true()
}

pub fn text_from_snapshot_rebrands_to_the_loading_replica_test() {
  let #(state, op, _) = must_insert(new_a(), 0, "seed")
  let assert Ok(state) = text_kernel.ack_local(state, op)
  let summary = channel.TextSummary(state.sequenced)

  let loaded = channel.from_snapshot(summary, replica: "b")
  let assert channel.TextState(kernel) = loaded
  kernel.replica_id |> expect.to_equal(replica_id.new("b"))
  text_kernel.value(kernel) |> expect.to_equal("seed")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("seed")
}

pub fn detached_text_attach_carries_optimistic_state_and_promotes_test() {
  let assert channel.TextState(kernel) =
    channel.new(channel.InitText, replica: "a")
  let assert Ok(#(kernel, _, Some(_))) = text_kernel.insert(kernel, 0, "draft")
  let detached = channel.TextState(kernel)

  // Attach snapshot carries the optimistic (pending-inclusive) text, unlike
  // `snapshot`, which would only carry the empty sequenced state.
  let assert channel.TextSummary(sequenced) = channel.snapshot(detached)
  text_kernel.from_sequenced(sequenced, replica_id.new("a"))
  |> text_kernel.value
  |> expect.to_equal("")

  let assert channel.TextSummary(optimistic) = channel.attach_snapshot(detached)
  text_kernel.from_sequenced(optimistic, replica_id.new("a"))
  |> text_kernel.value
  |> expect.to_equal("draft")

  let promoted = channel.attach_state(detached, replica: "a")
  let assert channel.TextState(promoted_kernel) = promoted
  text_kernel.value(promoted_kernel) |> expect.to_equal("draft")
  text_kernel.sequenced_value(promoted_kernel) |> expect.to_equal("draft")
  promoted_kernel.pending |> expect.to_equal([])
}

pub fn text_apply_remote_emits_changed_event_test() {
  let local = channel.new(channel.InitText, replica: "a")
  let #(_, remote_op, _) = must_insert(new_a(), 0, "hi")

  let assert Ok(#(channel.TextState(kernel), events, owed)) =
    channel.apply_remote(local, channel.TextOp(remote_op), no_op_meta())
  owed |> expect.to_equal([])
  events
  |> expect.to_equal([channel.TextEvent(text_kernel.TextChanged("hi"))])
  text_kernel.value(kernel) |> expect.to_equal("hi")
}

pub fn text_apply_remote_wrong_op_type_is_wrong_channel_type_test() {
  let state = channel.new(channel.InitText, replica: "a")
  channel.apply_remote(
    state,
    channel.CounterOp(counter_kernel.Increment(1)),
    no_op_meta(),
  )
  |> expect.to_equal(
    Error(channel.WrongChannelType(
      "remote op does not match the text channel it was routed to",
    )),
  )
}

pub fn text_ack_local_commits_pending_to_sequenced_test() {
  let assert channel.TextState(kernel) =
    channel.new(channel.InitText, replica: "a")
  let assert Ok(#(kernel, _, Some(text_kernel.Submission(op, message_id)))) =
    text_kernel.insert(kernel, 0, "a")
  let detached = channel.TextState(kernel)

  let assert Ok(#(channel.TextState(acked), events, resolution)) =
    channel.ack_local(
      detached,
      channel.TextOp(op),
      channel.TextMeta(message_id),
      no_op_meta(),
    )
  events |> expect.to_equal([])
  resolution |> expect.to_equal(None)
  text_kernel.sequenced_value(acked) |> expect.to_equal("a")
  acked.pending |> expect.to_equal([])
}

pub fn text_ack_local_rejects_mismatched_local_meta_test() {
  let assert channel.TextState(kernel) =
    channel.new(channel.InitText, replica: "a")
  let assert Ok(#(kernel, _, Some(text_kernel.Submission(op, _)))) =
    text_kernel.insert(kernel, 0, "a")
  let detached = channel.TextState(kernel)

  channel.ack_local(detached, channel.TextOp(op), channel.NoMeta, no_op_meta())
  |> expect.to_equal(
    Error(channel.UnexpectedAck("text ack is missing its local message id")),
  )
}

pub fn text_ack_local_wrong_message_id_is_unexpected_ack_test() {
  let assert channel.TextState(kernel) =
    channel.new(channel.InitText, replica: "a")
  let assert Ok(#(kernel, _, Some(text_kernel.Submission(op, message_id)))) =
    text_kernel.insert(kernel, 0, "a")
  let detached = channel.TextState(kernel)

  channel.ack_local(
    detached,
    channel.TextOp(op),
    channel.TextMeta(message_id + 1),
    no_op_meta(),
  )
  |> expect.to_equal(
    Error(channel.UnexpectedAck("expected pending message " <> "0")),
  )
}

pub fn other_channel_ack_rejects_text_meta_test() {
  let assert channel.CounterState(kernel) =
    channel.new(channel.InitCounter, replica: "a")
  let #(kernel, _, op, _) = counter_kernel.increment(kernel, 3)
  let detached = channel.CounterState(kernel)

  channel.ack_local(
    detached,
    channel.CounterOp(op),
    channel.TextMeta(0),
    no_op_meta(),
  )
  |> expect.to_equal(
    Error(channel.UnexpectedAck("counter ack has text metadata")),
  )
}

pub fn text_same_shape_matches_identical_insert_test() {
  let #(_, op, _) = must_insert(new_a(), 0, "Ada")

  channel.same_shape(channel.TextOp(op), channel.TextOp(op))
  |> expect.to_be_true()
}

pub fn text_same_shape_rejects_changed_insert_diagnostic_test() {
  let #(_, op, _) = must_insert(new_a(), 0, "Ada")
  let assert text_kernel.Insert(_, _, delta) = op
  let altered = text_kernel.Insert(1, "Eve", delta)

  channel.same_shape(channel.TextOp(op), channel.TextOp(altered))
  |> expect.to_be_false()
}

pub fn text_same_shape_rejects_tampered_insert_delta_test() {
  let #(_, op, _) = must_insert(new_a(), 0, "Ada")
  let assert text_kernel.Insert(index, value, _) = op
  let tampered = text_kernel.Insert(index, value, tampered_delta())

  channel.same_shape(channel.TextOp(op), channel.TextOp(tampered))
  |> expect.to_be_false()
}

pub fn text_same_shape_matches_identical_delete_range_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "hello")
  let #(_, op, _) = must_delete_range(state, 1, 3)

  channel.same_shape(channel.TextOp(op), channel.TextOp(op))
  |> expect.to_be_true()
}

pub fn text_same_shape_rejects_changed_delete_range_diagnostic_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "hello")
  let #(_, op, _) = must_delete_range(state, 1, 3)
  let assert text_kernel.DeleteRange(_, _, delta) = op
  let altered = text_kernel.DeleteRange(0, 2, delta)

  channel.same_shape(channel.TextOp(op), channel.TextOp(altered))
  |> expect.to_be_false()
}

pub fn text_same_shape_rejects_tampered_delete_range_delta_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "hello")
  let #(_, op, _) = must_delete_range(state, 1, 3)
  let assert text_kernel.DeleteRange(start, end, _) = op
  let tampered = text_kernel.DeleteRange(start, end, tampered_delta())

  channel.same_shape(channel.TextOp(op), channel.TextOp(tampered))
  |> expect.to_be_false()
}

pub fn text_same_shape_matches_identical_replace_range_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "hello")
  let #(_, op, _) = must_replace_range(state, 0, 1, "H")

  channel.same_shape(channel.TextOp(op), channel.TextOp(op))
  |> expect.to_be_true()
}

pub fn text_same_shape_rejects_changed_replace_range_diagnostic_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "hello")
  let #(_, op, _) = must_replace_range(state, 0, 1, "H")
  let assert text_kernel.ReplaceRange(_, _, _, delta) = op
  let altered = text_kernel.ReplaceRange(0, 1, "J", delta)

  channel.same_shape(channel.TextOp(op), channel.TextOp(altered))
  |> expect.to_be_false()
}

pub fn text_same_shape_rejects_tampered_replace_range_delta_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "hello")
  let #(_, op, _) = must_replace_range(state, 0, 1, "H")
  let assert text_kernel.ReplaceRange(start, end, value, _) = op
  let tampered = text_kernel.ReplaceRange(start, end, value, tampered_delta())

  channel.same_shape(channel.TextOp(op), channel.TextOp(tampered))
  |> expect.to_be_false()
}

pub fn text_same_shape_matches_identical_append_test() {
  let #(_, op, _) = must_append(new_a(), "tail")

  channel.same_shape(channel.TextOp(op), channel.TextOp(op))
  |> expect.to_be_true()
}

pub fn text_same_shape_rejects_changed_append_diagnostic_test() {
  let #(_, op, _) = must_append(new_a(), "tail")
  let assert text_kernel.Append(_, delta) = op
  let altered = text_kernel.Append("other", delta)

  channel.same_shape(channel.TextOp(op), channel.TextOp(altered))
  |> expect.to_be_false()
}

pub fn text_same_shape_rejects_tampered_append_delta_test() {
  let #(_, op, _) = must_append(new_a(), "tail")
  let assert text_kernel.Append(value, _) = op
  let tampered = text_kernel.Append(value, tampered_delta())

  channel.same_shape(channel.TextOp(op), channel.TextOp(tampered))
  |> expect.to_be_false()
}

pub fn text_same_shape_rejects_cross_constructor_comparisons_test() {
  let #(state, insert_op, _) = must_insert(new_a(), 0, "hello")
  let #(state, delete_op, _) = must_delete_range(state, 0, 1)
  let #(state, replace_op, _) = must_replace_range(state, 0, 1, "H")
  let #(_, append_op, _) = must_append(state, "!")

  channel.same_shape(channel.TextOp(insert_op), channel.TextOp(delete_op))
  |> expect.to_be_false()
  channel.same_shape(channel.TextOp(delete_op), channel.TextOp(replace_op))
  |> expect.to_be_false()
  channel.same_shape(channel.TextOp(replace_op), channel.TextOp(append_op))
  |> expect.to_be_false()
  channel.same_shape(channel.TextOp(append_op), channel.TextOp(insert_op))
  |> expect.to_be_false()
}

pub fn text_same_snapshot_compares_canonical_encoding_test() {
  let #(state, op, _) = must_insert(new_a(), 0, "same")
  let assert Ok(state) = text_kernel.ack_local(state, op)
  let ours = channel.TextSummary(state.sequenced)
  let echoed = channel.TextSummary(state.sequenced)

  channel.same_snapshot(ours, echoed) |> expect.to_be_true()
}

pub fn text_discovers_no_nested_handles_test() {
  // Insert text that looks like a serialized handle payload; text never
  // parses its content for nested handles, so this must still return [].
  let handle_shaped_string = "{\"handle\":\"child\"}"
  let #(state, _, _) = must_insert(new_a(), 0, handle_shaped_string)
  channel.handle_addresses(channel.TextState(state)) |> expect.to_equal([])
}

pub fn text_kernel_rollback_is_reachable_from_channel_ops_test() {
  let #(state, first, _) = must_insert(new_a(), 0, "a")
  let #(state, second, second_id) = must_insert(state, 1, "b")

  let assert Ok(#(state, events)) =
    text_kernel.rollback(state, second, second_id)
  text_kernel.value(state) |> expect.to_equal("a")
  events |> expect.to_equal([text_kernel.TextChanged("a")])

  channel.same_shape(channel.TextOp(first), channel.TextOp(first))
  |> expect.to_be_true()
}

pub fn text_kernel_stash_replay_reproduces_channel_op_test() {
  let #(_, stashed_op, _) = must_insert(new_a(), 0, "resumed")

  let #(state, events, replayed_op, message_id) =
    text_kernel.apply_stashed_op(new_a(), stashed_op)

  text_kernel.value(state) |> expect.to_equal("resumed")
  events |> expect.to_equal([text_kernel.TextChanged("resumed")])
  channel.same_shape(channel.TextOp(replayed_op), channel.TextOp(stashed_op))
  |> expect.to_be_true()

  let assert Ok(acked) =
    text_kernel.ack_local_with_message_id(state, replayed_op, message_id)
  text_kernel.sequenced_value(acked) |> expect.to_equal("resumed")
}

pub fn text_kernel_cache_coherence_holds_after_remote_and_local_edits_test() {
  let #(state_a, local_op, _) = must_insert(new_a(), 0, "a")
  let #(_, remote_op, _) = must_insert(new_a(), 0, "b")
  let #(state_a, _) = text_kernel.apply_remote(state_a, remote_op)

  text_kernel.check_cache_coherence(state_a) |> expect.to_equal(Ok(Nil))

  let assert Ok(state_a) = text_kernel.ack_local(state_a, local_op)
  text_kernel.check_cache_coherence(state_a) |> expect.to_equal(Ok(Nil))
}
