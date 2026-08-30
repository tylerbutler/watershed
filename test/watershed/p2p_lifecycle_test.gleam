import gleam/json
import gleam/list
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

/// Deliver every operation in order via `apply_p2p_remote`, asserting each
/// merge succeeds. Mirrors how a p2p peer folds a batch of remote operations
/// over its channel state.
fn deliver(
  state: channel.ChannelState,
  operations: List(channel.ChannelOperation),
) -> channel.ChannelState {
  list.fold(operations, state, fn(state, operation) {
    let assert Ok(#(state, _events)) =
      channel.apply_p2p_remote(state, operation)
    state
  })
}

/// Assert that delivering `operations` to a fresh replica (from `make`)
/// converges to the same `read` result regardless of delivery order, and stays
/// there even when the whole batch is redelivered a second time — exhaustively,
/// across every permutation of `operations`, not just one shuffled sample.
/// Returns the converged value so callers can also check it against a
/// hand-computed expectation.
fn assert_converges(
  make: fn() -> channel.ChannelState,
  operations: List(channel.ChannelOperation),
  read: fn(channel.ChannelState) -> a,
) -> a {
  let expected = read(deliver(make(), operations))
  list.permutations(operations)
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
    Ok(_)
    | Error(channel.UnexpectedAck(..))
    | Error(channel.WrongChannelType(..))
    | Error(channel.CorruptRemoteOperation(..)) ->
      panic as "expected Error(channel.UnsupportedP2p(_))"
  }
}

// --- local commit invariants: visible + confirmed update together, pending
// --- stays empty, for every `supports_p2p` kernel. --------------------------

pub fn pn_counter_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitPnCounter, replica: "a")
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.PnCounterEdit(7))

  events
  |> expect.to_equal([channel.PnCounterEvent(pn_counter_kernel.Updated(7, 7))])

  let assert channel.PnCounterState(kernel) = state
  kernel.pending |> expect.to_equal([])
  pn_counter_kernel.value(kernel) |> expect.to_equal(7)
  pn_counter_kernel.sequenced_value(kernel) |> expect.to_equal(7)
}

pub fn or_map_tally_local_edit_commits_immediately_test() -> Nil {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.OrMapIncrementEdit("score", 4))

  let assert channel.OrMapState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_map_kernel.get(kernel, "score")
  |> expect.to_equal(Ok(or_map_kernel.Tally(4)))
  or_map_kernel.sequenced_entries(kernel)
  |> expect.to_equal(or_map_kernel.entries(kernel))
}

pub fn or_map_register_local_edit_commits_immediately_test() -> Nil {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(
      state,
      channel.OrMapSetRegisterEdit("name", "Ann", 1),
    )

  let assert channel.OrMapState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_map_kernel.get(kernel, "name")
  |> expect.to_equal(Ok(or_map_kernel.Register("Ann")))
  or_map_kernel.sequenced_entries(kernel)
  |> expect.to_equal(or_map_kernel.entries(kernel))
}

pub fn or_map_remove_local_edit_commits_immediately_test() -> Nil {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.OrMapIncrementEdit("score", 4))
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.OrMapRemoveEdit("score"))

  let assert channel.OrMapState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_map_kernel.get(kernel, "score") |> expect.to_equal(Error(Nil))
}

pub fn or_set_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitOrSet, replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.OrSetAddEdit("x"))

  let assert channel.OrSetState(kernel) = state
  kernel.pending |> expect.to_equal([])
  or_set_kernel.values(kernel) |> expect.to_equal(["x"])
  or_set_kernel.sequenced_values(kernel) |> expect.to_equal(["x"])
}

pub fn g_set_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitGSet, replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.GSetAddEdit("x"))

  let assert channel.GSetState(kernel) = state
  kernel.pending |> expect.to_equal([])
  g_set_kernel.values(kernel) |> expect.to_equal(["x"])
  g_set_kernel.sequenced_values(kernel) |> expect.to_equal(["x"])
}

pub fn two_p_set_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitTwoPSet, replica: "a")
  let assert Ok(#(state, _events, _operation)) =
    channel.apply_p2p_local(state, channel.TwoPSetAddEdit("x"))

  let assert channel.TwoPSetState(kernel) = state
  kernel.pending |> expect.to_equal([])
  two_p_set_kernel.values(kernel) |> expect.to_equal(["x"])
  two_p_set_kernel.sequenced_values(kernel) |> expect.to_equal(["x"])
}

pub fn sequence_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _events, _operation)) =
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

pub fn sequence_delete_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(state, events, _operation)) =
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

pub fn sequence_move_local_edit_commits_immediately_test() -> Nil {
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
  let assert Ok(#(state, events, _operation)) =
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

pub fn sequence_replace_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(
      state,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(state, events, _operation)) =
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

pub fn text_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hi"))

  events |> expect.to_equal([channel.TextEvent(text_kernel.TextChanged("hi"))])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("hi")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("hi")
}

pub fn text_delete_range_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hello"))
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.TextDeleteRangeEdit(1, 3))

  events
  |> expect.to_equal([channel.TextEvent(text_kernel.TextChanged("hlo"))])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("hlo")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("hlo")
}

pub fn text_replace_range_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hello"))
  let assert Ok(#(state, events, _operation)) =
    channel.apply_p2p_local(state, channel.TextReplaceRangeEdit(0, 5, "world"))

  events
  |> expect.to_equal([channel.TextEvent(text_kernel.TextChanged("world"))])

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("world")
  text_kernel.sequenced_value(kernel) |> expect.to_equal("world")
}

pub fn text_append_local_edit_commits_immediately_test() -> Nil {
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, _, _)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, "hello "))
  let assert Ok(#(state, events, _operation)) =
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

pub fn text_empty_edit_still_commits_an_operation_test() -> Nil {
  // Unlike the server-backed `insert`, the p2p path always reports an operation
  // — there is no pending queue to spare from a content-free entry, so even a
  // no-operation edit (inserting "") is harmless to commit and broadcast.
  let state = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(state, events, operation)) =
    channel.apply_p2p_local(state, channel.TextInsertEdit(0, ""))

  events |> expect.to_equal([])
  case operation {
    channel.TextOperation(text_kernel.Insert(0, "", _delta)) -> Nil
    channel.TextOperation(text_kernel.Insert(..))
    | channel.TextOperation(text_kernel.DeleteRange(..))
    | channel.TextOperation(text_kernel.ReplaceRange(..))
    | channel.TextOperation(text_kernel.Append(..))
    | channel.MapOperation(..)
    | channel.CounterOperation(..)
    | channel.PnCounterOperation(..)
    | channel.OrMapOperation(..)
    | channel.OrSetOperation(..)
    | channel.GSetOperation(..)
    | channel.TwoPSetOperation(..)
    | channel.RegisterCollectionOperation(..)
    | channel.ClaimsOperation(..)
    | channel.TaskManagerOperation(..)
    | channel.PactMapOperation(..)
    | channel.JsonOtOperation(..)
    | channel.DirectoryOperation(..)
    | channel.OrderedCollectionOperation(..)
    | channel.SequenceOperation(..)
    | channel.RichTextOperation(..) ->
      panic as "expected an Insert(0, \"\", _) op even for an empty edit"
  }

  let assert channel.TextState(kernel) = state
  kernel.pending |> expect.to_equal([])
  text_kernel.value(kernel) |> expect.to_equal("")
}

// --- dispatch rejection: ineligible channels and mismatched edits/operations.
// -----

pub fn apply_p2p_local_rejects_ineligible_channel_test() -> Nil {
  let state = channel.new(channel.InitMap, replica: "a")
  channel.apply_p2p_local(state, channel.PnCounterEdit(1))
  |> expect_unsupported_p2p
}

pub fn apply_p2p_remote_rejects_ineligible_channel_test() -> Nil {
  let state = channel.new(channel.InitMap, replica: "a")
  let counter = channel.new(channel.InitPnCounter, replica: "b")
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(counter, channel.PnCounterEdit(1))

  channel.apply_p2p_remote(state, operation) |> expect_unsupported_p2p
}

pub fn apply_p2p_local_rejects_mismatched_edit_test() -> Nil {
  let state = channel.new(channel.InitPnCounter, replica: "a")
  channel.apply_p2p_local(state, channel.OrSetAddEdit("x"))
  |> expect_unsupported_p2p
}

pub fn apply_p2p_remote_rejects_mismatched_operation_test() -> Nil {
  let pn_counter_state = channel.new(channel.InitPnCounter, replica: "a")
  let text_state = channel.new(channel.InitText, replica: "b")
  let assert Ok(#(_, _, text_operation)) =
    channel.apply_p2p_local(text_state, channel.TextAppendEdit("z"))

  channel.apply_p2p_remote(pn_counter_state, text_operation)
  |> expect_unsupported_p2p
}

pub fn or_map_increment_against_register_mode_is_rejected_test() -> Nil {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: "a")
  channel.apply_p2p_local(state, channel.OrMapIncrementEdit("k", 1))
  |> expect_unsupported_p2p
}

pub fn or_map_set_register_against_tally_mode_is_rejected_test() -> Nil {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "a")
  channel.apply_p2p_local(state, channel.OrMapSetRegisterEdit("k", "v", 1))
  |> expect_unsupported_p2p
}

pub fn sequence_edit_out_of_bounds_is_rejected_test() -> Nil {
  let state = channel.new(channel.InitSequence, replica: "a")
  channel.apply_p2p_local(state, channel.SequenceDeleteEdit(0))
  |> expect_unsupported_p2p
}

pub fn text_edit_out_of_bounds_is_rejected_test() -> Nil {
  let state = channel.new(channel.InitText, replica: "a")
  channel.apply_p2p_local(state, channel.TextDeleteRangeEdit(0, 1))
  |> expect_unsupported_p2p
}

// --- convergence: operations authored via `apply_p2p_local` on distinct
// replicas --- converge on a third replica no matter the delivery order, and
// survive --- a full redelivery of the batch (idempotence).
// --------------------------

fn pn_counter_operation(
  replica: String,
  amount: Int,
) -> channel.ChannelOperation {
  let state = channel.new(channel.InitPnCounter, replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(state, channel.PnCounterEdit(amount))
  operation
}

pub fn pn_counter_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let operations = [
    pn_counter_operation("a", 5),
    pn_counter_operation("b", -2),
    pn_counter_operation("c", 10),
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
    operations,
    read,
  )
  |> expect.to_equal(#(13, 13, True))
}

fn or_map_increment_operation(
  replica: String,
  amount: Int,
) -> channel.ChannelOperation {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(state, channel.OrMapIncrementEdit("score", amount))
  operation
}

pub fn or_map_tally_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let operations = [
    or_map_increment_operation("a", 3),
    or_map_increment_operation("b", -1),
    or_map_increment_operation("c", 4),
  ]
  let read = fn(state) {
    let assert channel.OrMapState(kernel) = state
    #(or_map_kernel.get(kernel, "score"), kernel.pending == [])
  }

  assert_converges(
    fn() {
      channel.new(channel.InitOrMap(or_map_kernel.TallyMode), replica: "z")
    },
    operations,
    read,
  )
  |> expect.to_equal(#(Ok(or_map_kernel.Tally(6)), True))
}

fn or_map_register_operation(
  replica: String,
  value: String,
  timestamp: Int,
) -> channel.ChannelOperation {
  let state =
    channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(
      state,
      channel.OrMapSetRegisterEdit("name", value, timestamp),
    )
  operation
}

pub fn or_map_register_p2p_converges_on_highest_timestamp_test() -> Nil {
  let operations = [
    or_map_register_operation("a", "first", 5),
    or_map_register_operation("b", "second", 10),
  ]
  let read = fn(state) {
    let assert channel.OrMapState(kernel) = state
    #(or_map_kernel.get(kernel, "name"), kernel.pending == [])
  }

  assert_converges(
    fn() {
      channel.new(channel.InitOrMap(or_map_kernel.RegisterMode), replica: "z")
    },
    operations,
    read,
  )
  |> expect.to_equal(#(Ok(or_map_kernel.Register("second")), True))
}

fn or_set_add_operation(
  replica: String,
  element: String,
) -> channel.ChannelOperation {
  let state = channel.new(channel.InitOrSet, replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(state, channel.OrSetAddEdit(element))
  operation
}

pub fn or_set_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let operations = [
    or_set_add_operation("a", "x"),
    or_set_add_operation("b", "y"),
    or_set_add_operation("c", "z"),
  ]
  let read = fn(state) {
    let assert channel.OrSetState(kernel) = state
    #(or_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitOrSet, replica: "o") },
    operations,
    read,
  )
  |> expect.to_equal(#(["x", "y", "z"], True))
}

pub fn or_set_add_then_observed_remove_converges_across_order_test() -> Nil {
  let state_a = channel.new(channel.InitOrSet, replica: "a")
  let assert Ok(#(_, _, add_operation)) =
    channel.apply_p2p_local(state_a, channel.OrSetAddEdit("x"))

  let state_b = channel.new(channel.InitOrSet, replica: "b")
  let assert Ok(#(state_b, _)) =
    channel.apply_p2p_remote(state_b, add_operation)
  let assert Ok(#(state_b, _, remove_operation)) =
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
    [add_operation, remove_operation],
    read,
  )
  |> expect.to_equal(#([], True))
}

fn g_set_add_operation(
  replica: String,
  element: String,
) -> channel.ChannelOperation {
  let state = channel.new(channel.InitGSet, replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(state, channel.GSetAddEdit(element))
  operation
}

pub fn g_set_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let operations = [
    g_set_add_operation("a", "x"),
    g_set_add_operation("b", "y"),
    g_set_add_operation("c", "z"),
  ]
  let read = fn(state) {
    let assert channel.GSetState(kernel) = state
    #(g_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitGSet, replica: "o") },
    operations,
    read,
  )
  |> expect.to_equal(#(["x", "y", "z"], True))
}

fn two_p_set_add_operation(
  replica: String,
  element: String,
) -> channel.ChannelOperation {
  let state = channel.new(channel.InitTwoPSet, replica: replica)
  let assert Ok(#(_, _, operation)) =
    channel.apply_p2p_local(state, channel.TwoPSetAddEdit(element))
  operation
}

pub fn two_p_set_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let operations = [
    two_p_set_add_operation("a", "x"),
    two_p_set_add_operation("b", "y"),
    two_p_set_add_operation("c", "z"),
  ]
  let read = fn(state) {
    let assert channel.TwoPSetState(kernel) = state
    #(two_p_set_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitTwoPSet, replica: "o") },
    operations,
    read,
  )
  |> expect.to_equal(#(["x", "y", "z"], True))
}

pub fn two_p_set_add_then_remove_converges_across_order_test() -> Nil {
  let state_a = channel.new(channel.InitTwoPSet, replica: "a")
  let assert Ok(#(state_a, _, add_operation)) =
    channel.apply_p2p_local(state_a, channel.TwoPSetAddEdit("x"))
  let assert Ok(#(state_a, _, remove_operation)) =
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
    [add_operation, remove_operation],
    read,
  )
  |> expect.to_equal(#([], True))
}

/// Three replicas concurrently insert a distinct element at index 0, none
/// having observed the others yet — the sequence CRDT's identities (not
/// index) must give every replica's insert a stable position so delivery
/// order never matters.
pub fn sequence_concurrent_inserts_converge_across_order_test() -> Nil {
  let insert_at = fn(replica: String, value: String) -> channel.ChannelOperation {
    let state = channel.new(channel.InitSequence, replica: replica)
    let assert Ok(#(_, _, operation)) =
      channel.apply_p2p_local(
        state,
        channel.SequenceInsertEdit(0, json.string(value)),
      )
    operation
  }
  let operations = [
    insert_at("a", "a"),
    insert_at("b", "b"),
    insert_at("c", "c"),
  ]
  let read = fn(state) {
    let assert channel.SequenceState(kernel) = state
    #(sequence_kernel.values(kernel), kernel.pending == [])
  }

  let #(values, pending_empty) =
    assert_converges(
      fn() { channel.new(channel.InitSequence, replica: "o") },
      operations,
      read,
    )

  pending_empty |> expect.to_equal(True)
  list.length(values) |> expect.to_equal(3)
  list.contains(values, json.string("a")) |> expect.to_equal(True)
  list.contains(values, json.string("b")) |> expect.to_equal(True)
  list.contains(values, json.string("c")) |> expect.to_equal(True)
}

pub fn sequence_delete_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let state_a = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(_, _, insert_operation)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(0, json.string("x")),
    )

  let state_b = channel.new(channel.InitSequence, replica: "b")
  let assert Ok(#(state_b, _)) =
    channel.apply_p2p_remote(state_b, insert_operation)
  let assert Ok(#(state_b, _, delete_operation)) =
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
    [insert_operation, delete_operation],
    read,
  )
  |> expect.to_equal(#([], True))
}

pub fn sequence_replace_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let state_a = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(_, _, insert_operation)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(0, json.string("x")),
    )

  let state_b = channel.new(channel.InitSequence, replica: "b")
  let assert Ok(#(state_b, _)) =
    channel.apply_p2p_remote(state_b, insert_operation)
  let assert Ok(#(_, _, replace_operation)) =
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
    [insert_operation, replace_operation],
    read,
  )
  |> expect.to_equal(#([json.string("y")], True))
}

/// A move authored on top of two already-merged concurrent inserts. The
/// move operation's identity refers to the item it targets, so it is delivered
/// here alongside the inserts it depends on; every order (and a full
/// redelivered duplicate of the batch) must still converge.
pub fn sequence_move_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let state_a = channel.new(channel.InitSequence, replica: "a")
  let assert Ok(#(state_a, _, insert_a_operation)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(0, json.string("a")),
    )
  let assert Ok(#(_, _, insert_b_operation)) =
    channel.apply_p2p_local(
      state_a,
      channel.SequenceInsertEdit(1, json.string("b")),
    )

  let state_c = channel.new(channel.InitSequence, replica: "c")
  let assert Ok(#(state_c, _)) =
    channel.apply_p2p_remote(state_c, insert_a_operation)
  let assert Ok(#(state_c, _)) =
    channel.apply_p2p_remote(state_c, insert_b_operation)
  let assert Ok(#(_, _, move_operation)) =
    channel.apply_p2p_local(state_c, channel.SequenceMoveEdit(1, 0))

  let read = fn(state) {
    let assert channel.SequenceState(kernel) = state
    #(sequence_kernel.values(kernel), kernel.pending == [])
  }

  assert_converges(
    fn() { channel.new(channel.InitSequence, replica: "o") },
    [insert_a_operation, insert_b_operation, move_operation],
    read,
  )
  |> expect.to_equal(#([json.string("b"), json.string("a")], True))
}

/// Three replicas concurrently insert a distinct character at index 0, none
/// having observed the others yet.
pub fn text_concurrent_inserts_converge_across_order_test() -> Nil {
  let insert_at = fn(replica: String, value: String) -> channel.ChannelOperation {
    let state = channel.new(channel.InitText, replica: replica)
    let assert Ok(#(_, _, operation)) =
      channel.apply_p2p_local(state, channel.TextInsertEdit(0, value))
    operation
  }
  let operations = [
    insert_at("a", "a"),
    insert_at("b", "b"),
    insert_at("c", "c"),
  ]
  let read = fn(state) {
    let assert channel.TextState(kernel) = state
    #(text_kernel.value(kernel), kernel.pending == [])
  }

  let #(value, pending_empty) =
    assert_converges(
      fn() { channel.new(channel.InitText, replica: "o") },
      operations,
      read,
    )

  pending_empty |> expect.to_equal(True)
  string.length(value) |> expect.to_equal(3)
  string.contains(value, "a") |> expect.to_equal(True)
  string.contains(value, "b") |> expect.to_equal(True)
  string.contains(value, "c") |> expect.to_equal(True)
}

pub fn text_delete_range_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let state_a = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(_, _, insert_operation)) =
    channel.apply_p2p_local(state_a, channel.TextInsertEdit(0, "hello"))

  let state_b = channel.new(channel.InitText, replica: "b")
  let assert Ok(#(state_b, _)) =
    channel.apply_p2p_remote(state_b, insert_operation)
  let assert Ok(#(state_b, _, delete_operation)) =
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
    [insert_operation, delete_operation],
    read,
  )
  |> expect.to_equal(#("hlo", True))
}

pub fn text_replace_range_p2p_converges_across_order_and_duplicates_test() -> Nil {
  let state_a = channel.new(channel.InitText, replica: "a")
  let assert Ok(#(_, _, insert_operation)) =
    channel.apply_p2p_local(state_a, channel.TextInsertEdit(0, "hello"))

  let state_b = channel.new(channel.InitText, replica: "b")
  let assert Ok(#(state_b, _)) =
    channel.apply_p2p_remote(state_b, insert_operation)
  let assert Ok(#(_, _, replace_operation)) =
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
    [insert_operation, replace_operation],
    read,
  )
  |> expect.to_equal(#("world", True))
}

/// Three replicas concurrently append a distinct character, none having
/// observed the others yet — `append` inserts at the end anchor, so this
/// is the same identity-based, order-independent guarantee as
/// `text_concurrent_inserts_converge_across_order_test`.
pub fn text_append_concurrent_converges_across_order_test() -> Nil {
  let append_operation = fn(replica: String, value: String) -> channel.ChannelOperation {
    let state = channel.new(channel.InitText, replica: replica)
    let assert Ok(#(_, _, operation)) =
      channel.apply_p2p_local(state, channel.TextAppendEdit(value))
    operation
  }
  let operations = [
    append_operation("a", "a"),
    append_operation("b", "b"),
    append_operation("c", "c"),
  ]
  let read = fn(state) {
    let assert channel.TextState(kernel) = state
    #(text_kernel.value(kernel), kernel.pending == [])
  }

  let #(value, pending_empty) =
    assert_converges(
      fn() { channel.new(channel.InitText, replica: "o") },
      operations,
      read,
    )

  pending_empty |> expect.to_equal(True)
  string.length(value) |> expect.to_equal(3)
  string.contains(value, "a") |> expect.to_equal(True)
  string.contains(value, "b") |> expect.to_equal(True)
  string.contains(value, "c") |> expect.to_equal(True)
}
