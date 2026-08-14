import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import startest/expect

import watershed/channel
import watershed/g_set_kernel
import watershed/or_map_kernel
import watershed/or_set_kernel
import watershed/pn_counter_kernel
import watershed/sequence_kernel
import watershed/text_kernel
import watershed/two_p_set_kernel

/// Deliver every op in order via `apply_p2p_remote`, asserting each merge
/// succeeds. Mirrors how a p2p peer folds a batch of remote ops over its
/// channel state.
fn deliver(
  state: channel.ChannelState,
  ops: List(channel.ChannelOp),
) -> channel.ChannelState {
  list.fold(ops, state, fn(state, op) {
    let assert Ok(#(state, _events)) = channel.apply_p2p_remote(state, op)
    state
  })
}

/// Assert that delivering `ops` to a fresh replica (from `make`) converges
/// to the same `read` result regardless of delivery order, and stays there
/// even when the whole batch is redelivered a second time — exhaustively,
/// across every permutation of `ops`, not just one shuffled sample. Returns
/// the converged value so callers can also check it against a hand-computed
/// expectation.
fn assert_converges(
  make: fn() -> channel.ChannelState,
  ops: List(channel.ChannelOp),
  read: fn(channel.ChannelState) -> a,
) -> a {
  let expected = read(deliver(make(), ops))
  list.permutations(ops)
  |> list.each(fn(order) {
    deliver(make(), order) |> read |> expect.to_equal(expected)
    deliver(make(), list.append(order, order))
    |> read
    |> expect.to_equal(expected)
  })
  expected
}

fn expect_unsupported_p2p(result: Result(a, channel.ChannelError)) -> Nil {
  case result {
    Error(channel.UnsupportedP2p(_)) -> Nil
    _ -> panic as "expected Error(channel.UnsupportedP2p(_))"
  }
}

// --- local commit invariants: visible + confirmed update together, pending
// --- stays empty, for every `supports_p2p` kernel. --------------------------

pub fn pn_counter_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitPnCounter, replica: "a")
  let assert Ok(#(state, events, _op)) =
    channel.apply_p2p_local(state, channel.PnCounterEdit(7))

  events
  |> expect.to_equal([channel.PnCounterEvent(pn_counter_kernel.Updated(7, 7))])

  let assert channel.PnCounterState(kernel) = state
  kernel.pending |> expect.to_equal([])
  pn_counter_kernel.value(kernel) |> expect.to_equal(7)
  pn_counter_kernel.sequenced_value(kernel) |> expect.to_equal(7)
}

pub fn or_map_tally_local_edit_commits_immediately_test() {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "a")
  let assert Ok(#(state, _events, _op)) =
    channel.apply_p2p_local(state, channel.OrMapIncrementEdit("score", 4))

  let assert channel.OrMapState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_map_kernel.get(kernel, "score")
  |> expect.to_equal(Some(or_map_kernel.Tally(4)))
  or_map_kernel.sequenced_entries(kernel)
  |> expect.to_equal(or_map_kernel.entries(kernel))
}

pub fn or_map_register_local_edit_commits_immediately_test() {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: "a")
  let assert Ok(#(state, _events, _op)) =
    channel.apply_p2p_local(
      state,
      channel.OrMapSetRegisterEdit("name", "Ann", 1),
    )

  let assert channel.OrMapState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_map_kernel.get(kernel, "name")
  |> expect.to_equal(Some(or_map_kernel.Register("Ann")))
  or_map_kernel.sequenced_entries(kernel)
  |> expect.to_equal(or_map_kernel.entries(kernel))
}

pub fn or_map_remove_local_edit_commits_immediately_test() {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "a")
  let assert Ok(#(state, _events, _op)) =
    channel.apply_p2p_local(state, channel.OrMapIncrementEdit("score", 4))
  let assert Ok(#(state, _events, _op)) =
    channel.apply_p2p_local(state, channel.OrMapRemoveEdit("score"))

  let assert channel.OrMapState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_map_kernel.get(kernel, "score") |> expect.to_equal(None)
}

pub fn or_set_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitOrSet, replica: "a")
  let assert Ok(#(state, _events, _op)) =
    channel.apply_p2p_local(state, channel.OrSetAddEdit("x"))

  let assert channel.OrSetState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_set_kernel.values(kernel) |> expect.to_equal(["x"])
  or_set_kernel.sequenced_values(kernel) |> expect.to_equal(["x"])
}

pub fn g_set_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitGSet, replica: "a")
  let assert Ok(#(state, _events, _op)) =
    channel.apply_p2p_local(state, channel.GSetAddEdit("x"))

  let assert channel.GSetState(kernel) = state
  kernel.pending |> expect.to_equal([])
  g_set_kernel.values(kernel) |> expect.to_equal(["x"])
  g_set_kernel.sequenced_values(kernel) |> expect.to_equal(["x"])
}

pub fn two_p_set_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitTwoPSet, replica: "a")
  let assert Ok(#(state, _events, _op)) =
    channel.apply_p2p_local(state, channel.TwoPSetAddEdit("x"))

  let assert channel.TwoPSetState(kernel) = state
  kernel.pending |> expect.to_equal([])
  two_p_set_kernel.values(kernel) |> expect.to_equal(["x"])
  two_p_set_kernel.sequenced_values(kernel) |> expect.to_equal(["x"])
}

pub fn sequence_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _events, _op)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(0, json.string("a")),
    )

  let assert channel.SequenceState(kernel) = state
  kernel.pending |> expect.to_equal([])
  sequence_kernel.values(kernel) |> expect.to_equal([json.string("a")])
  sequence_kernel.sequenced_values(kernel)
  |> expect.to_equal([json.string("a")])
}

pub fn sequence_delete_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(state, events, _op)) =
    channel.apply_p2p_local(state, channel.SequenceDeleteEdit(0))

  events
  |> expect.to_equal([
    channel.SequenceEvent(sequence_kernel.SequenceChanged([])),
  ])

  let assert channel.SequenceState(kernel) = state
  kernel.pending |> expect.to_equal([])
  sequence_kernel.values(kernel) |> expect.to_equal([])
  sequence_kernel.sequenced_values(kernel) |> expect.to_equal([])
}

pub fn sequence_move_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(1, json.string("b")),
    )
  let assert Ok(#(state, events, _op)) =
    channel.apply_p2p_local(state, channel.SequenceMoveEdit(1, 0))

  events
  |> expect.to_equal([
    channel.SequenceEvent(
      sequence_kernel.SequenceChanged([json.string("b"), json.string("a")]),
    ),
  ])

  let assert channel.SequenceState(kernel) = state
  kernel.pending |> expect.to_equal([])
  sequence_kernel.values(kernel)
  |> expect.to_equal([json.string("b"), json.string("a")])
  sequence_kernel.sequenced_values(kernel)
  |> expect.to_equal([json.string("b"), json.string("a")])
}

pub fn sequence_replace_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(state, events, _op)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceReplaceEdit(0, json.string("b")),
    )

  events
  |> expect.to_equal([
    channel.SequenceEvent(sequence_kernel.SequenceChanged([json.string("b")])),
  ])

  let assert channel.SequenceState(kernel) = state
  kernel.pending |> expect.to_equal([])
  sequence_kernel.values(kernel) |> expect.to_equal([json.string("b")])
  sequence_kernel.sequenced_values(kernel)
  |> expect.to_equal([json.string("b")])
}

pub fn text_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, events, _op)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hi"))

  events |> expect.to_equal([channel.TextEvent(text_kernel.TextChanged("hi"))])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("hi")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("hi")
}

pub fn text_delete_range_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hello"))
  let assert Ok(#(state, events, _op)) =
    channel.apply_p2p_local(state, channel.TextDeleteRangeEdit(1, 3))

  events
  |> expect.to_equal([channel.TextEvent(text_kernel.TextChanged("hlo"))])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("hlo")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("hlo")
}

pub fn text_replace_range_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hello"))
  let assert Ok(#(state, events, _op)) =
    channel.apply_p2p_local(state, channel.TextReplaceRangeEdit(0, 5, "world"))

  events
  |> expect.to_equal([channel.TextEvent(text_kernel.TextChanged("world"))])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("world")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("world")
}

pub fn text_append_local_edit_commits_immediately_test() {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hello "))
  let assert Ok(#(state, events, _op)) =
    channel.apply_p2p_local(state, channel.TextAppendEdit("world"))

  events
  |> expect.to_equal([
    channel.TextEvent(text_kernel.TextChanged("hello world")),
  ])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("hello world")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("hello world")
}

pub fn text_empty_edit_still_commits_an_op_test() {
  // Unlike the server-backed `insert`, the p2p path always reports an op —
  // there is no pending queue to spare from a content-free entry, so even a
  // no-op edit (inserting "") is harmless to commit and broadcast.
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, events, op)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, ""))

  events |> expect.to_equal([])
  case op {
    channel.TextOp(text_kernel.Insert(0, "", _delta)) -> Nil
    _ -> panic as "expected an Insert(0, \"\", _) op even for an empty edit"
  }

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("")
}

// --- dispatch rejection: ineligible channels and mismatched edits/ops. -----

pub fn apply_p2p_local_rejects_ineligible_channel_test() {
  let state = channel.new(channel.InitMap, replica: "a")
  channel.apply_p2p_local(state, channel.PnCounterEdit(1))
  |> expect_unsupported_p2p
}

pub fn apply_p2p_remote_rejects_ineligible_channel_test() {
  let state = channel.new(channel.InitMap, replica: "a")
  let counter = channel.new(channel.InitPnCounter, replica: "b")
  let assert Ok(#(_, _, op)) =
    channel.apply_p2p_local(counter, channel.PnCounterEdit(1))

  channel.apply_p2p_remote(state, op) |> expect_unsupported_p2p
}

pub fn apply_p2p_local_rejects_mismatched_edit_test() {
  let state = channel.new(channel.InitPnCounter, replica: "a")
  channel.apply_p2p_local(state, channel.OrSetAddEdit("x"))
  |> expect_unsupported_p2p
}

pub fn apply_p2p_remote_rejects_mismatched_op_test() {
  let pn_counter_state = channel.new(channel.InitPnCounter, replica: "a")
  let text_state = channel.new(channel.InitText, replica: "b")
  let assert Ok(#(_, _, text_op)) =
    channel.apply_p2p_local(text_state, channel.TextAppendEdit("z"))

  channel.apply_p2p_remote(pn_counter_state, text_op) |> expect_unsupported_p2p
}

pub fn or_map_increment_against_register_mode_is_rejected_test() {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: "a")
  channel.apply_p2p_local(state, channel.OrMapIncrementEdit("k", 1))
  |> expect_unsupported_p2p
}

pub fn or_map_set_register_against_tally_mode_is_rejected_test() {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "a")
  channel.apply_p2p_local(state, channel.OrMapSetRegisterEdit("k", "v", 1))
  |> expect_unsupported_p2p
}

pub fn sequence_edit_out_of_bounds_is_rejected_test() {
  let state = channel.new(channel.InitSequence, replica: "a")
  channel.apply_p2p_local(state, channel.SequenceDeleteEdit(0))
  |> expect_unsupported_p2p
}

pub fn text_edit_out_of_bounds_is_rejected_test() {
  let state = channel.new(channel.InitText, replica: "a")
  channel.apply_p2p_local(state, channel.TextDeleteRangeEdit(0, 1))
  |> expect_unsupported_p2p
}

// --- convergence: ops authored via `apply_p2p_local` on distinct replicas
// --- converge on a third replica no matter the delivery order, and survive
// --- a full redelivery of the batch (idempotence). --------------------------

fn pn_counter_op(replica: String, amount: Int) -> channel.ChannelOp {
  let state = channel.new(channel.InitPnCounter, replica: replica)
  let assert Ok(#(_, _, op)) =
    channel.apply_p2p_local(state, channel.PnCounterEdit(amount))
  op
}

pub fn pn_counter_p2p_converges_across_order_and_duplicates_test() {
  let ops = [
    pn_counter_op("a", 5),
    pn_counter_op("b", -2),
    pn_counter_op("c", 10),
  ]
  let read = fn(state) {
    let assert channel.PnCounterState(kernel) = state
    #(
      pn_counter_kernel.value(kernel),
      pn_counter_kernel.sequenced_value(kernel),
      kernel.pending == [],
    )
  }

  assert_converges(
    fn() { channel.new(channel.InitPnCounter, replica: "z") },
    ops,
    read,
  )
  |> expect.to_equal(#(13, 13, True))
}

fn or_map_increment_op(replica: String, amount: Int) -> channel.ChannelOp {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: replica)
  let assert Ok(#(_, _, op)) =
    channel.apply_p2p_local(state, channel.OrMapIncrementEdit("score", amount))
  op
}

pub fn or_map_tally_p2p_converges_across_order_and_duplicates_test() {
  let ops = [
    or_map_increment_op("a", 3),
    or_map_increment_op("b", -1),
    or_map_increment_op("c", 4),
  ]
  let read = fn(state) {
    let assert channel.OrMapState(kernel) = state
    #(or_map_kernel.get(kernel, "score"), kernel.pending == [])
  }

  assert_converges(
    fn() {
      channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "z")
    },
    ops,
    read,
  )
  |> expect.to_equal(#(Some(or_map_kernel.Tally(6)), True))
}

fn or_map_register_op(
  replica: String,
  value: String,
  timestamp: Int,
) -> channel.ChannelOp {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: replica)
  let assert Ok(#(_, _, op)) =
    channel.apply_p2p_local(
      state,
      channel.OrMapSetRegisterEdit("name", value, timestamp),
    )
  op
}

pub fn or_map_register_p2p_converges_on_highest_timestamp_test() {
  let ops = [
    or_map_register_op("a", "first", 5),
    or_map_register_op("b", "second", 10),
  ]
  let read = fn(state) {
    let assert channel.OrMapState(kernel) = state
    #(or_map_kernel.get(kernel, "name"), kernel.pending == [])
  }

  assert_converges(
    fn() {
      channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: "z")
    },
    ops,
    read,
  )
  |> expect.to_equal(#(Some(or_map_kernel.Register("second")), True))
}

fn or_set_add_op(replica: String, element: String) -> channel.ChannelOp {
  let state = channel.new(channel.InitOrSet, replica: replica)
  let assert Ok(#(_, _, op)) =
    channel.apply_p2p_local(state, channel.OrSetAddEdit(element))
  op
}

pub fn or_set_p2p_converges_across_order_and_duplicates_test() {
  let ops = [
    or_set_add_op("a", "x"),
    or_set_add_op("b", "y"),
    or_set_add_op("c", "z"),
  ]
  let read = fn(state) {
    let assert channel.OrSetState(kernel) = state
    #(or_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitOrSet, replica: "o") },
    ops,
    read,
  )
  |> expect.to_equal(#(["x", "y", "z"], True))
}

pub fn or_set_add_then_observed_remove_converges_across_order_test() {
  let state_a = channel.new(channel.InitOrSet, replica: "a")
  let assert Ok(#(_, _, add_op)) =
    channel.apply_p2p_local(state_a, channel.OrSetAddEdit("x"))

  let state_b = channel.new(channel.InitOrSet, replica: "b")
  let assert Ok(#(state_b, _)) = channel.apply_p2p_remote(state_b, add_op)
  let assert Ok(#(state_b, _, remove_op)) =
    channel.apply_p2p_local(state_b, channel.OrSetRemoveEdit("x"))

  // The remove edit itself commits immediately too: no pending entry.
  let assert channel.OrSetState(remove_kernel) = state_b
  remove_kernel.pending |> expect.to_equal([])
  or_set_kernel.values(remove_kernel) |> expect.to_equal([])

  let read = fn(state) {
    let assert channel.OrSetState(kernel) = state
    #(or_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitOrSet, replica: "o") },
    [add_op, remove_op],
    read,
  )
  |> expect.to_equal(#([], True))
}

fn g_set_add_op(replica: String, element: String) -> channel.ChannelOp {
  let state = channel.new(channel.InitGSet, replica: replica)
  let assert Ok(#(_, _, op)) =
    channel.apply_p2p_local(state, channel.GSetAddEdit(element))
  op
}

pub fn g_set_p2p_converges_across_order_and_duplicates_test() {
  let ops = [
    g_set_add_op("a", "x"),
    g_set_add_op("b", "y"),
    g_set_add_op("c", "z"),
  ]
  let read = fn(state) {
    let assert channel.GSetState(kernel) = state
    #(g_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitGSet, replica: "o") },
    ops,
    read,
  )
  |> expect.to_equal(#(["x", "y", "z"], True))
}

fn two_p_set_add_op(replica: String, element: String) -> channel.ChannelOp {
  let state = channel.new(channel.InitTwoPSet, replica: replica)
  let assert Ok(#(_, _, op)) =
    channel.apply_p2p_local(state, channel.TwoPSetAddEdit(element))
  op
}

pub fn two_p_set_p2p_converges_across_order_and_duplicates_test() {
  let ops = [
    two_p_set_add_op("a", "x"),
    two_p_set_add_op("b", "y"),
    two_p_set_add_op("c", "z"),
  ]
  let read = fn(state) {
    let assert channel.TwoPSetState(kernel) = state
    #(two_p_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitTwoPSet, replica: "o") },
    ops,
    read,
  )
  |> expect.to_equal(#(["x", "y", "z"], True))
}

pub fn two_p_set_add_then_remove_converges_across_order_test() {
  let state_a = channel.new(channel.InitTwoPSet, replica: "a")
  let assert Ok(#(state_a, _, add_op)) =
    channel.apply_p2p_local(state_a, channel.TwoPSetAddEdit("x"))
  let assert Ok(#(state_a, _, remove_op)) =
    channel.apply_p2p_local(state_a, channel.TwoPSetRemoveEdit("x"))

  // The remove edit itself commits immediately too: no pending entry.
  let assert channel.TwoPSetState(remove_kernel) = state_a
  remove_kernel.pending |> expect.to_equal([])
  two_p_set_kernel.values(remove_kernel) |> expect.to_equal([])

  let read = fn(state) {
    let assert channel.TwoPSetState(kernel) = state
    #(two_p_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitTwoPSet, replica: "o") },
    [add_op, remove_op],
    read,
  )
  |> expect.to_equal(#([], True))
}

/// Three replicas concurrently insert a distinct element at index 0, none
/// having observed the others yet — the sequence CRDT's identities (not
/// index) must give every replica's insert a stable position so delivery
/// order never matters.
pub fn sequence_concurrent_inserts_converge_across_order_test() {
  let insert_at = fn(replica: String, value: String) -> channel.ChannelOp {
    let state = channel.new(channel.InitSequence, replica: replica)
    let assert Ok(#(_, _, op)) =
      channel.apply_p2p_local(
        state,
        channel.SequenceInsertEdit(0, json.string(value)),
      )
    op
  }
  let ops = [insert_at("a", "a"), insert_at("b", "b"), insert_at("c", "c")]
  let read = fn(state) {
    let assert channel.SequenceState(kernel) = state
    #(sequence_kernel.values(kernel), kernel.pending == [])
  }

  let #(values, pending_empty) =
    assert_converges(
      fn() { channel.new(channel.InitSequence, replica: "o") },
      ops,
      read,
    )

  pending_empty |> expect.to_equal(True)
  list.length(values) |> expect.to_equal(3)
  list.contains(values, json.string("a")) |> expect.to_equal(True)
  list.contains(values, json.string("b")) |> expect.to_equal(True)
  list.contains(values, json.string("c")) |> expect.to_equal(True)
}

pub fn sequence_delete_p2p_converges_across_order_and_duplicates_test() {
  let state_a = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(_, _, insert_op)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(0, json.string("x")),
    )

  let state_b = channel.new(channel.InitSequence, replica: "b")
  let assert Ok(#(state_b, _)) = channel.apply_p2p_remote(state_b, insert_op)
  let assert Ok(#(state_b, _, delete_op)) =
    channel.apply_p2p_local(state_b, channel.SequenceDeleteEdit(0))

  // The delete edit itself commits immediately too: no pending entry.
  let assert channel.SequenceState(delete_kernel) = state_b
  delete_kernel.pending |> expect.to_equal([])
  sequence_kernel.values(delete_kernel) |> expect.to_equal([])

  let read = fn(state) {
    let assert channel.SequenceState(kernel) = state
    #(sequence_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitSequence, replica: "o") },
    [insert_op, delete_op],
    read,
  )
  |> expect.to_equal(#([], True))
}

pub fn sequence_replace_p2p_converges_across_order_and_duplicates_test() {
  let state_a = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(_, _, insert_op)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(0, json.string("x")),
    )

  let state_b = channel.new(channel.InitSequence, replica: "b")
  let assert Ok(#(state_b, _)) = channel.apply_p2p_remote(state_b, insert_op)
  let assert Ok(#(_, _, replace_op)) =
    channel.apply_p2p_local(
      state_b,
      channel.SequenceReplaceEdit(0, json.string("y")),
    )

  let read = fn(state) {
    let assert channel.SequenceState(kernel) = state
    #(sequence_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitSequence, replica: "o") },
    [insert_op, replace_op],
    read,
  )
  |> expect.to_equal(#([json.string("y")], True))
}

/// A move authored on top of two already-merged concurrent inserts. The
/// move op's identity refers to the item it targets, so it is delivered
/// here alongside the inserts it depends on; every order (and a full
/// redelivered duplicate of the batch) must still converge.
pub fn sequence_move_p2p_converges_across_order_and_duplicates_test() {
  let state_a = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state_a, _, insert_a_op)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(_, _, insert_b_op)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(1, json.string("b")),
    )

  let state_c = channel.new(channel.InitSequence, replica: "c")
  let assert Ok(#(state_c, _)) = channel.apply_p2p_remote(state_c, insert_a_op)
  let assert Ok(#(state_c, _)) = channel.apply_p2p_remote(state_c, insert_b_op)
  let assert Ok(#(_, _, move_op)) =
    channel.apply_p2p_local(state_c, channel.SequenceMoveEdit(1, 0))

  let read = fn(state) {
    let assert channel.SequenceState(kernel) = state
    #(sequence_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitSequence, replica: "o") },
    [insert_a_op, insert_b_op, move_op],
    read,
  )
  |> expect.to_equal(#([json.string("b"), json.string("a")], True))
}

/// Three replicas concurrently insert a distinct character at index 0, none
/// having observed the others yet.
pub fn text_concurrent_inserts_converge_across_order_test() {
  let insert_at = fn(replica: String, value: String) -> channel.ChannelOp {
    let state = channel.new(channel.InitText, replica: replica)
    let assert Ok(#(_, _, op)) =
      channel.apply_p2p_local(state, channel.TextInsertEdit(0, value))
    op
  }
  let ops = [insert_at("a", "a"), insert_at("b", "b"), insert_at("c", "c")]
  let read = fn(state) {
    let assert channel.TextState(kernel) = state
    #(text_kernel.value(kernel), kernel.pending == [])
  }

  let #(value, pending_empty) =
    assert_converges(
      fn() { channel.new(channel.InitText, replica: "o") },
      ops,
      read,
    )

  pending_empty |> expect.to_equal(True)
  string.length(value) |> expect.to_equal(3)
  string.contains(value, "a") |> expect.to_equal(True)
  string.contains(value, "b") |> expect.to_equal(True)
  string.contains(value, "c") |> expect.to_equal(True)
}

pub fn text_delete_range_p2p_converges_across_order_and_duplicates_test() {
  let state_a = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(_, _, insert_op)) =
    channel.apply_p2p_local(state_a, channel.TextInsertEdit(0, "hello"))

  let state_b = channel.new(channel.InitText, replica: "b")
  let assert Ok(#(state_b, _)) = channel.apply_p2p_remote(state_b, insert_op)
  let assert Ok(#(state_b, _, delete_op)) =
    channel.apply_p2p_local(state_b, channel.TextDeleteRangeEdit(1, 3))

  // The delete edit itself commits immediately too: no pending entry.
  let assert channel.TextState(delete_kernel) = state_b
  delete_kernel.pending |> expect.to_equal([])
  text_kernel.value(delete_kernel) |> expect.to_equal("hlo")

  let read = fn(state) {
    let assert channel.TextState(kernel) = state
    #(text_kernel.value(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitText, replica: "o") },
    [insert_op, delete_op],
    read,
  )
  |> expect.to_equal(#("hlo", True))
}

pub fn text_replace_range_p2p_converges_across_order_and_duplicates_test() {
  let state_a = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(_, _, insert_op)) =
    channel.apply_p2p_local(state_a, channel.TextInsertEdit(0, "hello"))

  let state_b = channel.new(channel.InitText, replica: "b")
  let assert Ok(#(state_b, _)) = channel.apply_p2p_remote(state_b, insert_op)
  let assert Ok(#(_, _, replace_op)) =
    channel.apply_p2p_local(
      state_b,
      channel.TextReplaceRangeEdit(0, 5, "world"),
    )

  let read = fn(state) {
    let assert channel.TextState(kernel) = state
    #(text_kernel.value(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitText, replica: "o") },
    [insert_op, replace_op],
    read,
  )
  |> expect.to_equal(#("world", True))
}

/// Three replicas concurrently append a distinct character, none having
/// observed the others yet — `append` inserts at the end anchor, so this
/// is the same identity-based, order-independent guarantee as
/// `text_concurrent_inserts_converge_across_order_test`.
pub fn text_append_concurrent_converges_across_order_test() {
  let append_op = fn(replica: String, value: String) -> channel.ChannelOp {
    let state = channel.new(channel.InitText, replica: replica)
    let assert Ok(#(_, _, op)) =
      channel.apply_p2p_local(state, channel.TextAppendEdit(value))
    op
  }
  let ops = [append_op("a", "a"), append_op("b", "b"), append_op("c", "c")]
  let read = fn(state) {
    let assert channel.TextState(kernel) = state
    #(text_kernel.value(kernel), kernel.pending == [])
  }

  let #(value, pending_empty) =
    assert_converges(
      fn() { channel.new(channel.InitText, replica: "o") },
      ops,
      read,
    )

  pending_empty |> expect.to_equal(True)
  string.length(value) |> expect.to_equal(3)
  string.contains(value, "a") |> expect.to_equal(True)
  string.contains(value, "b") |> expect.to_equal(True)
  string.contains(value, "c") |> expect.to_equal(True)
}
