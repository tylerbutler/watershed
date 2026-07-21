import gleam/dynamic/decode
import gleam/json
import lattice_core/replica_id
import startest/expect
import watershed/sequence_kernel

fn new_a() -> sequence_kernel.SequenceState {
  sequence_kernel.new(replica_id.new("a"))
}

fn ack(
  state: sequence_kernel.SequenceState,
  op: sequence_kernel.SequenceOp,
) -> sequence_kernel.SequenceState {
  let assert Ok(state) = sequence_kernel.ack_local(state, op)
  state
}

pub fn insert_delete_move_replace_are_optimistic_test() {
  let assert Ok(#(state, _, insert_a, id0)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  id0 |> expect.to_equal(0)

  let assert Ok(#(state, _, insert_b, id1)) =
    sequence_kernel.insert(state, 1, json.string("b"))
  id1 |> expect.to_equal(1)

  let assert Ok(#(state, _, move_b, id2)) = sequence_kernel.move(state, 1, 0)
  id2 |> expect.to_equal(2)

  let assert Ok(#(state, events, replace_nine, id3)) =
    sequence_kernel.replace(state, 1, json.int(9))
  id3 |> expect.to_equal(3)

  events
  |> expect.to_equal([
    sequence_kernel.SequenceChanged([json.string("b"), json.int(9)]),
  ])

  case state.pending {
    [
      sequence_kernel.PendingOp(op: pending_insert_a, message_id: pending_id0),
      sequence_kernel.PendingOp(op: pending_insert_b, message_id: pending_id1),
      sequence_kernel.PendingOp(op: pending_move_b, message_id: pending_id2),
      sequence_kernel.PendingOp(op: pending_replace_nine, message_id: pending_id3),
    ] -> {
      pending_insert_a |> expect.to_equal(insert_a)
      pending_insert_b |> expect.to_equal(insert_b)
      pending_move_b |> expect.to_equal(move_b)
      pending_replace_nine |> expect.to_equal(replace_nine)
      pending_id0 |> expect.to_equal(0)
      pending_id1 |> expect.to_equal(1)
      pending_id2 |> expect.to_equal(2)
      pending_id3 |> expect.to_equal(3)
    }
    _ -> panic as "expected one pending op per local edit"
  }

  case replace_nine {
    sequence_kernel.Replace(1, value, _) -> value |> expect.to_equal(json.int(9))
    _ -> panic as "expected replace op"
  }

  let assert Ok(#(semantic_state, _, _, _)) =
    sequence_kernel.insert(
      new_a(),
      0,
      json.object([#("a", json.int(1)), #("b", json.int(2))]),
    )
  let assert Ok(#(semantic_state, semantic_events, semantic_replace, semantic_id)) =
    sequence_kernel.replace(
      semantic_state,
      0,
      json.object([#("b", json.int(2)), #("a", json.int(1))]),
    )

  semantic_id |> expect.to_equal(1)
  semantic_events |> expect.to_equal([])
  sequence_kernel.values(semantic_state)
  |> expect.to_equal([json.object([#("b", json.int(2)), #("a", json.int(1))])])
  case semantic_state.pending {
    [
      sequence_kernel.PendingOp(_, 0),
      sequence_kernel.PendingOp(op: pending_semantic_replace, message_id: pending_semantic_id),
    ] -> {
      pending_semantic_replace |> expect.to_equal(semantic_replace)
      pending_semantic_id |> expect.to_equal(1)
    }
    _ -> panic as "expected semantic replace to stay one pending op"
  }
  case semantic_replace {
    sequence_kernel.Replace(0, value, _) ->
      value
      |> expect.to_equal(json.object([#("b", json.int(2)), #("a", json.int(1))]))
    _ -> panic as "expected semantic replace op"
  }

  let assert Ok(#(state, _, _, id4)) = sequence_kernel.delete(state, 0)
  id4 |> expect.to_equal(4)
  sequence_kernel.values(state) |> expect.to_equal([json.int(9)])
  sequence_kernel.sequenced_values(state) |> expect.to_equal([])
  sequence_kernel.length(state) |> expect.to_equal(1)
}

pub fn invalid_indexes_return_edit_errors_test() {
  sequence_kernel.insert(new_a(), 1, json.null())
  |> expect.to_equal(Error(sequence_kernel.InsertOutOfBounds(1, 0)))

  sequence_kernel.delete(new_a(), 0)
  |> expect.to_equal(Error(sequence_kernel.DeleteOutOfBounds(0, 0)))

  sequence_kernel.move(new_a(), 0, 0)
  |> expect.to_equal(Error(sequence_kernel.MoveFromOutOfBounds(0, 0)))

  let assert Ok(#(move_state, _, _, _)) =
    sequence_kernel.insert(new_a(), 0, json.null())
  sequence_kernel.move(move_state, 0, 1)
  |> expect.to_equal(Error(sequence_kernel.MoveToOutOfBounds(1, 0)))

  sequence_kernel.replace(new_a(), 0, json.null())
  |> expect.to_equal(Error(sequence_kernel.ReplaceOutOfBounds(0, 0)))

  sequence_kernel.edit_error_detail(sequence_kernel.InsertOutOfBounds(1, 0))
  |> expect.to_equal("insert index 1 outside 0..0")
  sequence_kernel.edit_error_detail(sequence_kernel.DeleteOutOfBounds(0, 0))
  |> expect.to_equal("delete index 0 invalid for length 0")
  sequence_kernel.edit_error_detail(sequence_kernel.MoveFromOutOfBounds(0, 0))
  |> expect.to_equal("move source index 0 invalid for length 0")
  sequence_kernel.edit_error_detail(sequence_kernel.MoveToOutOfBounds(1, 0))
  |> expect.to_equal("move destination index 1 outside 0..0")
  sequence_kernel.edit_error_detail(sequence_kernel.ReplaceOutOfBounds(0, 0))
  |> expect.to_equal("replace index 0 invalid for length 0")
}

pub fn ack_is_view_transparent_and_remote_merge_is_idempotent_test() {
  let assert Ok(#(state_a, _, first_op, _)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  let assert Ok(#(state_a, _, second_op, _)) =
    sequence_kernel.insert(state_a, 1, json.string("b"))
  let before_ack = sequence_kernel.values(state_a)
  sequence_kernel.ack_local(state_a, second_op)
  |> expect.to_equal(Error(
    sequence_kernel.UnexpectedAck("expected pending message 0"),
  ))
  let state_a = ack(state_a, first_op)
  sequence_kernel.values(state_a) |> expect.to_equal(before_ack)
  let state_a = ack(state_a, second_op)
  sequence_kernel.values(state_a) |> expect.to_equal(before_ack)
  sequence_kernel.sequenced_values(state_a)
  |> expect.to_equal([json.string("a"), json.string("b")])

  let state_b = sequence_kernel.new(replica_id.new("b"))
  let #(state_b, first_events) = sequence_kernel.apply_remote(state_b, first_op)
  let #(state_b, second_events) = sequence_kernel.apply_remote(state_b, first_op)
  sequence_kernel.values(state_b) |> expect.to_equal([json.string("a")])
  first_events
  |> expect.to_equal([sequence_kernel.SequenceChanged([json.string("a")])])
  second_events |> expect.to_equal([])
}

pub fn ack_local_with_message_id_validates_message_id_test() {
  let assert Ok(#(state, _, op, message_id)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))

  sequence_kernel.ack_local_with_message_id(state, op, message_id + 1)
  |> expect.to_equal(Error(
    sequence_kernel.UnexpectedAck("expected pending message 0"),
  ))
  sequence_kernel.values(state) |> expect.to_equal([json.string("a")])
  sequence_kernel.sequenced_values(state) |> expect.to_equal([])
  state.pending |> expect.to_equal([sequence_kernel.PendingOp(op, message_id)])

  let assert Ok(state) =
    sequence_kernel.ack_local_with_message_id(state, op, message_id)
  sequence_kernel.values(state) |> expect.to_equal([json.string("a")])
  sequence_kernel.sequenced_values(state) |> expect.to_equal([json.string("a")])
}

pub fn apply_remote_replays_pending_and_preserves_view_after_ack_test() {
  let assert Ok(#(state_a, _, local_op, local_message_id)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  let assert Ok(#(_, _, remote_op, _)) =
    sequence_kernel.insert(
      sequence_kernel.new(replica_id.new("b")),
      0,
      json.string("b"),
    )

  let #(state_a, events) = sequence_kernel.apply_remote(state_a, remote_op)
  state_a.pending
  |> expect.to_equal([sequence_kernel.PendingOp(local_op, local_message_id)])
  sequence_kernel.values(state_a)
  |> expect.to_equal([json.string("a"), json.string("b")])
  events |> expect.to_equal([sequence_kernel.SequenceChanged(sequence_kernel.values(state_a))])
  sequence_kernel.check_cache_coherence(state_a) |> expect.to_equal(Ok(Nil))

  let assert Ok(state_a) =
    sequence_kernel.ack_local_with_message_id(state_a, local_op, local_message_id)
  sequence_kernel.values(state_a)
  |> expect.to_equal([json.string("a"), json.string("b")])
}

pub fn rollback_replays_remaining_pending_test() {
  let assert Ok(#(state, _, first, _)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  let assert Ok(#(state, _, second, second_id)) =
    sequence_kernel.insert(state, 1, json.string("b"))
  let assert Ok(#(state, events)) =
    sequence_kernel.rollback(state, second, second_id)

  sequence_kernel.values(state) |> expect.to_equal([json.string("a")])
  events
  |> expect.to_equal([
    sequence_kernel.SequenceChanged([json.string("a")]),
  ])
  ack(state, first)
  |> sequence_kernel.sequenced_values
  |> expect.to_equal([json.string("a")])
}

pub fn summary_round_trips_and_rebrands_test() {
  let assert Ok(#(state, _, op, _)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  let state = ack(state, op)
  let assert Ok(#(state, _, _, _)) =
    sequence_kernel.insert(state, 1, json.string("pending"))
  let raw = json.to_string(sequence_kernel.summary(state))
  let assert Ok(loaded) =
    sequence_kernel.from_summary(raw, replica_id.new("c"))
  sequence_kernel.values(loaded) |> expect.to_equal([json.string("a")])
  sequence_kernel.sequenced_values(loaded) |> expect.to_equal([json.string("a")])
  loaded.replica_id |> expect.to_equal(replica_id.new("c"))
  loaded.pending |> expect.to_equal([])
  loaded.next_pending_message_id |> expect.to_equal(0)
  let assert Ok(summary_self_id) =
    json.parse(
      json.to_string(sequence_kernel.summary(loaded)),
      decode.at(["state", "self_id"], replica_id.decoder()),
    )
  summary_self_id |> expect.to_equal(replica_id.new("c"))

  let assert Ok(#(loaded, _, op_c, message_id_c)) =
    sequence_kernel.insert(loaded, 1, json.string("c"))
  message_id_c |> expect.to_equal(0)
  ack(loaded, op_c)
  |> sequence_kernel.sequenced_values
  |> expect.to_equal([json.string("a"), json.string("c")])
}

pub fn apply_stashed_op_registers_pending_and_acks_by_message_id_test() {
  let assert Ok(#(_, _, op, _)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  let #(state, events, replayed_op, message_id) =
    sequence_kernel.apply_stashed_op(new_a(), op)

  sequence_kernel.values(state) |> expect.to_equal([json.string("a")])
  events
  |> expect.to_equal([sequence_kernel.SequenceChanged([json.string("a")])])
  replayed_op |> expect.to_equal(op)
  message_id |> expect.to_equal(0)
  state.pending
  |> expect.to_equal([sequence_kernel.PendingOp(replayed_op, message_id)])

  let assert Ok(state) =
    sequence_kernel.ack_local_with_message_id(state, replayed_op, message_id)
  sequence_kernel.sequenced_values(state) |> expect.to_equal([json.string("a")])
  sequence_kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
}

pub fn promote_attach_commits_optimistic_view_and_clears_pending_test() {
  let assert Ok(#(state, _, _, _)) =
    sequence_kernel.insert(new_a(), 0, json.string("a"))
  let assert Ok(#(state, _, _, _)) =
    sequence_kernel.insert(state, 1, json.string("b"))
  let state = sequence_kernel.promote_attach(state)

  sequence_kernel.values(state)
  |> expect.to_equal([json.string("a"), json.string("b")])
  sequence_kernel.sequenced_values(state)
  |> expect.to_equal([json.string("a"), json.string("b")])
  state.pending |> expect.to_equal([])
  sequence_kernel.check_cache_coherence(state) |> expect.to_equal(Ok(Nil))
}

pub fn concurrent_inserts_and_replace_delete_move_converge_test() {
  let state_a = new_a()
  let state_b = sequence_kernel.new(replica_id.new("b"))
  let assert Ok(#(state_a, _, insert_a, _)) =
    sequence_kernel.insert(state_a, 0, json.string("a"))
  let assert Ok(#(state_b, _, insert_b, _)) =
    sequence_kernel.insert(state_b, 0, json.string("b"))

  let #(state_a, _) =
    sequence_kernel.apply_remote(ack(state_a, insert_a), insert_b)
  let #(state_b, _) =
    sequence_kernel.apply_remote(ack(state_b, insert_b), insert_a)
  sequence_kernel.values(state_a) |> expect.to_equal(sequence_kernel.values(state_b))

  let assert Ok(#(state_a, _, replace_a, _)) =
    sequence_kernel.replace(state_a, 0, json.string("A"))
  let assert Ok(#(state_b, _, move_b, _)) = sequence_kernel.move(state_b, 0, 1)
  let #(state_a, _) =
    sequence_kernel.apply_remote(ack(state_a, replace_a), move_b)
  let #(state_b, _) =
    sequence_kernel.apply_remote(ack(state_b, move_b), replace_a)
  sequence_kernel.values(state_a) |> expect.to_equal(sequence_kernel.values(state_b))
}
