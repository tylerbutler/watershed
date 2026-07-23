import gleam/json
import gleam/option.{None, Some}
import lattice_core/replica_id
import lattice_sequence/sequence.{After, Before}
import startest/expect
import watershed/text_kernel

fn new_a() -> text_kernel.TextState {
  text_kernel.new(replica_id.new("a"))
}

fn new_b() -> text_kernel.TextState {
  text_kernel.new(replica_id.new("b"))
}

fn ack(
  state: text_kernel.TextState,
  op: text_kernel.TextOp,
) -> text_kernel.TextState {
  let assert Ok(state) = text_kernel.ack_local(state, op)
  state
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

fn must_append(
  state: text_kernel.TextState,
  value: String,
) -> #(text_kernel.TextState, text_kernel.TextOp, Int) {
  let assert #(state, _events, Some(text_kernel.Submission(op, message_id))) =
    text_kernel.append(state, value)
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

pub fn insert_delete_replace_append_are_optimistic_test() {
  let #(state, insert_a, id0) = must_insert(new_a(), 0, "hello")
  id0 |> expect.to_equal(0)
  text_kernel.value(state) |> expect.to_equal("hello")

  let #(state, append_op, id1) = must_append(state, " world")
  id1 |> expect.to_equal(1)
  text_kernel.value(state) |> expect.to_equal("hello world")

  let #(state, replace_op, id2) = must_replace_range(state, 0, 5, "goodbye")
  id2 |> expect.to_equal(2)
  text_kernel.value(state) |> expect.to_equal("goodbye world")

  let assert Ok(#(state, events, Some(text_kernel.Submission(delete_op, id3)))) =
    text_kernel.delete_range(state, 7, 8)
  id3 |> expect.to_equal(3)
  text_kernel.value(state) |> expect.to_equal("goodbyeworld")
  events |> expect.to_equal([text_kernel.TextChanged("goodbyeworld")])

  case state.pending {
    [
      text_kernel.PendingOp(op: pending_insert, message_id: pending_id0),
      text_kernel.PendingOp(op: pending_append, message_id: pending_id1),
      text_kernel.PendingOp(op: pending_replace, message_id: pending_id2),
      text_kernel.PendingOp(op: pending_delete, message_id: pending_id3),
    ] -> {
      pending_insert |> expect.to_equal(insert_a)
      pending_append |> expect.to_equal(append_op)
      pending_replace |> expect.to_equal(replace_op)
      pending_delete |> expect.to_equal(delete_op)
      pending_id0 |> expect.to_equal(0)
      pending_id1 |> expect.to_equal(1)
      pending_id2 |> expect.to_equal(2)
      pending_id3 |> expect.to_equal(3)
    }
    _ -> panic as "expected one pending op per local edit"
  }

  text_kernel.sequenced_value(state) |> expect.to_equal("")
  text_kernel.length(state) |> expect.to_equal(12)
}

pub fn valid_empty_edits_are_no_ops_test() {
  let #(base, _, _) = must_insert(new_a(), 0, "hello")

  text_kernel.insert(base, 2, "")
  |> expect.to_equal(Ok(#(base, [], None)))
  text_kernel.delete_range(base, 2, 2)
  |> expect.to_equal(Ok(#(base, [], None)))
  text_kernel.replace_range(base, 2, 2, "")
  |> expect.to_equal(Ok(#(base, [], None)))
  text_kernel.append(base, "")
  |> expect.to_equal(#(base, [], None))

  // Empty edits still validate bounds first.
  text_kernel.insert(base, 99, "")
  |> expect.to_equal(Error(text_kernel.InsertOutOfBounds(99, 5)))
  text_kernel.delete_range(base, 2, 99)
  |> expect.to_equal(Error(text_kernel.DeleteRangeOutOfBounds(2, 99, 5)))
  text_kernel.replace_range(base, 2, 99, "")
  |> expect.to_equal(Error(text_kernel.ReplaceRangeOutOfBounds(2, 99, 5)))

  // An empty range replaced with real content is a genuine insert, and a
  // real range replaced with empty content is a genuine delete: neither is
  // a no-op.
  let assert Ok(#(_, events, Some(_))) =
    text_kernel.replace_range(base, 2, 2, "X")
  events |> expect.to_equal([text_kernel.TextChanged("heXllo")])
  let assert Ok(#(_, events, Some(_))) =
    text_kernel.replace_range(base, 2, 3, "")
  events |> expect.to_equal([text_kernel.TextChanged("helo")])
}

pub fn invalid_bounds_return_edit_errors_test() {
  text_kernel.insert(new_a(), 1, "x")
  |> expect.to_equal(Error(text_kernel.InsertOutOfBounds(1, 0)))
  text_kernel.delete_range(new_a(), 0, 1)
  |> expect.to_equal(Error(text_kernel.DeleteRangeOutOfBounds(0, 1, 0)))
  text_kernel.replace_range(new_a(), 0, 1, "x")
  |> expect.to_equal(Error(text_kernel.ReplaceRangeOutOfBounds(0, 1, 0)))
  text_kernel.substring(new_a(), 0, 1)
  |> expect.to_equal(Error(text_kernel.SubstringOutOfBounds(0, 1, 0)))

  text_kernel.edit_error_detail(text_kernel.InsertOutOfBounds(1, 0))
  |> expect.to_equal("insert index 1 outside 0..0")
  text_kernel.edit_error_detail(text_kernel.DeleteRangeOutOfBounds(0, 1, 0))
  |> expect.to_equal("delete range 0..1 invalid for length 0")
  text_kernel.edit_error_detail(text_kernel.ReplaceRangeOutOfBounds(0, 1, 0))
  |> expect.to_equal("replace range 0..1 invalid for length 0")
  text_kernel.edit_error_detail(text_kernel.SubstringOutOfBounds(0, 1, 0))
  |> expect.to_equal("substring range 0..1 invalid for length 0")
}

pub fn emoji_and_combining_grapheme_semantics_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "a👍é")
  text_kernel.length(state) |> expect.to_equal(3)
  text_kernel.value(state) |> expect.to_equal("a👍é")
  text_kernel.substring(state, 1, 2) |> expect.to_equal(Ok("👍"))
  text_kernel.substring(state, 0, 2) |> expect.to_equal(Ok("a👍"))

  let #(state, _, _) = must_insert(state, 3, "🎉🎉")
  text_kernel.length(state) |> expect.to_equal(5)
  text_kernel.value(state) |> expect.to_equal("a👍é🎉🎉")

  let #(state, _, _) = must_delete_range(state, 1, 2)
  text_kernel.value(state) |> expect.to_equal("aé🎉🎉")
  text_kernel.length(state) |> expect.to_equal(4)
}

pub fn multi_codepoint_graphemes_are_single_units_test() {
  // "e" + combining acute (U+0301) is one grapheme cluster rendered as "é",
  // distinct from the precomposed "é" used elsewhere in this suite. A
  // family emoji joined by ZWJ (U+200D) is also a single grapheme cluster
  // despite being many codepoints.
  let combining_e = "e\u{0301}"
  let family =
    "👩" <> "\u{200D}" <> "👩" <> "\u{200D}" <> "👧" <> "\u{200D}" <> "👦"
  let #(state, _, _) = must_insert(new_a(), 0, combining_e <> family)

  text_kernel.length(state) |> expect.to_equal(2)
  text_kernel.value(state) |> expect.to_equal(combining_e <> family)
  text_kernel.substring(state, 0, 1) |> expect.to_equal(Ok(combining_e))
  text_kernel.substring(state, 1, 2) |> expect.to_equal(Ok(family))

  // Inserting between the two graphemes lands at grapheme index 1, not at
  // some codepoint offset in the middle of either cluster.
  let #(state, _, _) = must_insert(state, 1, "|")
  text_kernel.length(state) |> expect.to_equal(3)
  text_kernel.value(state) |> expect.to_equal(combining_e <> "|" <> family)
  text_kernel.substring(state, 0, 1) |> expect.to_equal(Ok(combining_e))
  text_kernel.substring(state, 1, 2) |> expect.to_equal(Ok("|"))
  text_kernel.substring(state, 2, 3) |> expect.to_equal(Ok(family))

  // Deleting the family emoji removes the whole cluster in one grapheme
  // step, never splitting it.
  let #(state, _, _) = must_delete_range(state, 2, 3)
  text_kernel.value(state) |> expect.to_equal(combining_e <> "|")
  text_kernel.length(state) |> expect.to_equal(2)
}

pub fn replace_range_with_identical_text_sends_without_event_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "hello world")

  let assert Ok(#(next_state, events, Some(text_kernel.Submission(op, _)))) =
    text_kernel.replace_range(state, 0, 5, "hello")

  // The visible text is unchanged, so no TextChanged event fires...
  events |> expect.to_equal([])
  text_kernel.value(next_state) |> expect.to_equal("hello world")
  // ...but the replace is still a real edit: it queues a pending entry and
  // returns Some(Submission), so the caller still sends the op over the
  // wire (e.g. to reconcile concurrent replacements of the same range).
  case next_state.pending {
    [_, _] -> Nil
    _ -> panic as "expected the identical-text replace to queue a pending op"
  }
  case op {
    text_kernel.ReplaceRange(start: 0, end: 5, value: "hello", delta: _) -> Nil
    _ -> panic as "expected a ReplaceRange op for the identical-text replace"
  }
}

pub fn ack_is_view_transparent_and_remote_merge_is_idempotent_test() {
  let #(state_a, first_op, _) = must_insert(new_a(), 0, "a")
  let #(state_a, second_op, _) = must_insert(state_a, 1, "b")
  let before_ack = text_kernel.value(state_a)

  text_kernel.ack_local(state_a, second_op)
  |> expect.to_equal(
    Error(text_kernel.UnexpectedAck("expected pending message 0")),
  )

  let state_a = ack(state_a, first_op)
  text_kernel.value(state_a) |> expect.to_equal(before_ack)
  let state_a = ack(state_a, second_op)
  text_kernel.value(state_a) |> expect.to_equal(before_ack)
  text_kernel.sequenced_value(state_a) |> expect.to_equal("ab")

  let state_b = new_b()
  let #(state_b, first_events) = text_kernel.apply_remote(state_b, first_op)
  let #(state_b, second_events) = text_kernel.apply_remote(state_b, first_op)
  text_kernel.value(state_b) |> expect.to_equal("a")
  first_events |> expect.to_equal([text_kernel.TextChanged("a")])
  second_events |> expect.to_equal([])
}

pub fn ack_local_with_message_id_validates_message_id_test() {
  let #(state, op, message_id) = must_insert(new_a(), 0, "a")

  text_kernel.ack_local_with_message_id(state, op, message_id + 1)
  |> expect.to_equal(
    Error(text_kernel.UnexpectedAck("expected pending message 0")),
  )
  text_kernel.value(state) |> expect.to_equal("a")
  text_kernel.sequenced_value(state) |> expect.to_equal("")
  state.pending |> expect.to_equal([text_kernel.PendingOp(op, message_id)])

  let assert Ok(state) =
    text_kernel.ack_local_with_message_id(state, op, message_id)
  text_kernel.value(state) |> expect.to_equal("a")
  text_kernel.sequenced_value(state) |> expect.to_equal("a")
}

pub fn apply_remote_replays_pending_and_preserves_view_after_ack_test() {
  let #(state_a, local_op, local_message_id) = must_insert(new_a(), 0, "a")
  let #(_, remote_op, _) = must_insert(new_b(), 0, "b")

  let #(state_a, events) = text_kernel.apply_remote(state_a, remote_op)
  state_a.pending
  |> expect.to_equal([text_kernel.PendingOp(local_op, local_message_id)])
  text_kernel.value(state_a) |> expect.to_equal("ab")
  events |> expect.to_equal([text_kernel.TextChanged("ab")])
  text_kernel.check_cache_coherence(state_a) |> expect.to_equal(Ok(Nil))

  let assert Ok(state_a) =
    text_kernel.ack_local_with_message_id(state_a, local_op, local_message_id)
  text_kernel.value(state_a) |> expect.to_equal("ab")
}

pub fn rollback_replays_remaining_pending_test() {
  let #(state, first, _) = must_insert(new_a(), 0, "a")
  let #(state, second, second_id) = must_insert(state, 1, "b")
  let assert Ok(#(state, events)) =
    text_kernel.rollback(state, second, second_id)

  text_kernel.value(state) |> expect.to_equal("a")
  events |> expect.to_equal([text_kernel.TextChanged("a")])
  ack(state, first) |> text_kernel.sequenced_value |> expect.to_equal("a")
}

pub fn rollback_mismatch_is_a_kernel_error_test() {
  let #(state, first, first_id) = must_insert(new_a(), 0, "a")
  let #(state, _second, _) = must_insert(state, 1, "b")

  text_kernel.rollback(state, first, first_id)
  |> expect.to_equal(
    Error(text_kernel.UnexpectedRollback("expected newest pending message 1")),
  )
}

pub fn ack_local_on_empty_pending_queue_is_a_kernel_error_test() {
  let #(_, op, _) = must_insert(new_a(), 0, "a")

  text_kernel.ack_local(new_a(), op)
  |> expect.to_equal(Error(text_kernel.UnexpectedAck("pending queue is empty")))
  text_kernel.ack_local_with_message_id(new_a(), op, 0)
  |> expect.to_equal(Error(text_kernel.UnexpectedAck("pending queue is empty")))
}

pub fn rollback_on_empty_pending_queue_is_a_kernel_error_test() {
  let #(_, op, message_id) = must_insert(new_a(), 0, "a")

  text_kernel.rollback(new_a(), op, message_id)
  |> expect.to_equal(
    Error(text_kernel.UnexpectedRollback("pending queue is empty")),
  )
}

pub fn summary_round_trips_and_rebrands_test() {
  let #(state, op, _) = must_insert(new_a(), 0, "a")
  let state = ack(state, op)
  let #(state, _, _) = must_insert(state, 1, "pending")
  let raw = json.to_string(text_kernel.summary(state))

  let assert Ok(loaded) = text_kernel.from_summary(raw, replica_id.new("c"))
  text_kernel.value(loaded) |> expect.to_equal("a")
  text_kernel.sequenced_value(loaded) |> expect.to_equal("a")
  loaded.replica_id |> expect.to_equal(replica_id.new("c"))
  loaded.pending |> expect.to_equal([])
  loaded.next_pending_message_id |> expect.to_equal(0)

  let #(loaded, op_c, message_id_c) = must_insert(loaded, 1, "c")
  message_id_c |> expect.to_equal(0)
  ack(loaded, op_c) |> text_kernel.sequenced_value |> expect.to_equal("ac")
}

pub fn apply_stashed_op_registers_pending_and_acks_by_message_id_test() {
  let #(_, op, _) = must_insert(new_a(), 0, "a")
  let #(state, events, replayed_op, message_id) =
    text_kernel.apply_stashed_op(new_a(), op)

  text_kernel.value(state) |> expect.to_equal("a")
  events |> expect.to_equal([text_kernel.TextChanged("a")])
  replayed_op |> expect.to_equal(op)
  message_id |> expect.to_equal(0)
  state.pending
  |> expect.to_equal([text_kernel.PendingOp(replayed_op, message_id)])

  let assert Ok(state) =
    text_kernel.ack_local_with_message_id(state, replayed_op, message_id)
  text_kernel.sequenced_value(state) |> expect.to_equal("a")
  text_kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
}

pub fn promote_attach_commits_optimistic_view_and_clears_pending_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "a")
  let #(state, _, _) = must_append(state, "b")
  let state = text_kernel.promote_attach(state)

  text_kernel.value(state) |> expect.to_equal("ab")
  text_kernel.sequenced_value(state) |> expect.to_equal("ab")
  state.pending |> expect.to_equal([])
  text_kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
}

pub fn concurrent_inserts_at_same_index_converge_test() {
  let #(state_a, insert_a, _) = must_insert(new_a(), 0, "a")
  let #(state_b, insert_b, _) = must_insert(new_b(), 0, "b")

  let #(state_a, _) = text_kernel.apply_remote(ack(state_a, insert_a), insert_b)
  let #(state_b, _) = text_kernel.apply_remote(ack(state_b, insert_b), insert_a)

  text_kernel.value(state_a) |> expect.to_equal(text_kernel.value(state_b))
}

pub fn overlapping_delete_range_and_replace_range_converge_test() {
  let #(state_a, seed_op, _) = must_insert(new_a(), 0, "abcdef")
  let state_a = ack(state_a, seed_op)
  let #(state_b, _) = text_kernel.apply_remote(new_b(), seed_op)

  let #(state_a, delete_op, _) = must_delete_range(state_a, 1, 4)
  let #(state_b, replace_op, _) = must_replace_range(state_b, 2, 5, "XY")

  let #(state_a, _) =
    text_kernel.apply_remote(ack(state_a, delete_op), replace_op)
  let #(state_b, _) =
    text_kernel.apply_remote(ack(state_b, replace_op), delete_op)

  text_kernel.value(state_a) |> expect.to_equal(text_kernel.value(state_b))
  text_kernel.check_cache_coherence(state_a) |> expect.to_equal(Ok(Nil))
  text_kernel.check_cache_coherence(state_b) |> expect.to_equal(Ok(Nil))
}

pub fn append_concurrent_with_insert_converges_test() {
  let #(state_a, seed_op, _) = must_insert(new_a(), 0, "abc")
  let state_a = ack(state_a, seed_op)
  let #(state_b, _) = text_kernel.apply_remote(new_b(), seed_op)

  let #(state_a, append_op, _) = must_append(state_a, "z")
  let #(state_b, insert_op, _) = must_insert(state_b, 0, "y")

  let #(state_a, _) =
    text_kernel.apply_remote(ack(state_a, append_op), insert_op)
  let #(state_b, _) =
    text_kernel.apply_remote(ack(state_b, insert_op), append_op)

  text_kernel.value(state_a) |> expect.to_equal(text_kernel.value(state_b))
}

pub fn anchor_at_and_resolve_track_position_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "hello")
  let assert Ok(anchor) = text_kernel.anchor_at(state, 5, After)

  let #(state, _, _) = must_insert(state, 0, "say ")
  text_kernel.resolve_anchor(state, anchor) |> expect.to_equal(Ok(9))
}

pub fn start_and_end_anchors_track_boundaries_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "abc")

  text_kernel.resolve_anchor(state, text_kernel.start_anchor())
  |> expect.to_equal(Ok(0))
  text_kernel.resolve_anchor(state, text_kernel.end_anchor())
  |> expect.to_equal(Ok(3))

  let #(state, _, _) = must_append(state, "de")
  text_kernel.resolve_anchor(state, text_kernel.end_anchor())
  |> expect.to_equal(Ok(5))
}

pub fn anchor_at_out_of_bounds_returns_error_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "abc")

  text_kernel.anchor_at(state, 4, Before)
  |> expect.to_equal(Error(text_kernel.AnchorOutOfBounds(4, 3)))
  text_kernel.anchor_error_detail(text_kernel.AnchorOutOfBounds(4, 3))
  |> expect.to_equal("anchor index 4 outside 0..3")
  text_kernel.anchor_error_detail(text_kernel.UnknownAnchorTarget)
  |> expect.to_equal("anchor target is unknown; re-anchor")
}

pub fn anchor_json_round_trips_test() {
  let #(state, _, _) = must_insert(new_a(), 0, "abc")
  let assert Ok(anchor) = text_kernel.anchor_at(state, 2, After)

  let assert Ok(decoded) =
    text_kernel.anchor_from_json(
      json.to_string(text_kernel.anchor_to_json(anchor)),
    )
  text_kernel.resolve_anchor(state, decoded) |> expect.to_equal(Ok(2))
  decoded |> expect.to_equal(anchor)
}

pub fn anchor_from_json_rejects_malformed_json_test() {
  case text_kernel.anchor_from_json("not json") {
    Error(_) -> Nil
    Ok(_) -> panic as "expected malformed JSON to fail to decode"
  }

  case text_kernel.anchor_from_json("{}") {
    Error(_) -> Nil
    Ok(_) -> panic as "expected an empty object to fail to decode"
  }

  // Well-formed JSON with the wrong envelope type/version is also rejected.
  case
    text_kernel.anchor_from_json(
      json.to_string(
        json.object([
          #("type", json.string("not-an-anchor")),
          #("v", json.int(1)),
          #("anchor", json.object([#("kind", json.string("start"))])),
        ]),
      ),
    )
  {
    Error(_) -> Nil
    Ok(_) -> panic as "expected an unsupported envelope type to fail"
  }
}

pub fn anchor_resolves_unknown_target_until_merged_test() {
  let #(alice, seed_op, _) = must_insert(new_a(), 0, "abc")
  let alice = ack(alice, seed_op)

  let bob = text_kernel.from_sequenced(alice.sequenced, replica_id.new("b"))
  let #(bob, _, _) = must_insert(bob, 1, "x")
  let assert Ok(anchor) = text_kernel.anchor_at(bob, 1, Before)

  text_kernel.resolve_anchor(alice, anchor)
  |> expect.to_equal(Error(text_kernel.UnknownAnchorTarget))
}

pub fn anchor_survives_merge_of_concurrent_edits_test() {
  let #(base, seed_op, _) = must_insert(new_a(), 0, "abc")
  let base = ack(base, seed_op)
  let assert Ok(anchor) = text_kernel.anchor_at(base, 2, Before)

  let alice =
    text_kernel.from_sequenced(base.sequenced, replica_id.new("alice"))
  let #(alice, alice_op, _) = must_insert(alice, 0, "x")
  let bob = text_kernel.from_sequenced(base.sequenced, replica_id.new("bob"))
  let #(bob, bob_op, _) = must_delete_range(bob, 0, 1)

  let #(alice, _) = text_kernel.apply_remote(ack(alice, alice_op), bob_op)
  let #(bob, _) = text_kernel.apply_remote(ack(bob, bob_op), alice_op)

  text_kernel.value(alice) |> expect.to_equal(text_kernel.value(bob))

  let assert Ok(alice_resolved) = text_kernel.resolve_anchor(alice, anchor)
  let assert Ok(bob_resolved) = text_kernel.resolve_anchor(bob, anchor)
  text_kernel.substring(alice, alice_resolved, alice_resolved + 1)
  |> expect.to_equal(Ok("c"))
  text_kernel.substring(bob, bob_resolved, bob_resolved + 1)
  |> expect.to_equal(Ok("c"))
}
