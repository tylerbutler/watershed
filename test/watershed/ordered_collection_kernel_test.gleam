//// Unit suite for `ordered_collection_kernel`, ported from the core
//// ConsensusOrderedCollection queue/lifecycle semantics.

import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import startest/expect
import watershed/ordered_collection_kernel.{
  type AcquireOutcome, type OrderedEvent, type OrderedOperation, Acquire,
  Acquired, AcquiredItem, Add, Added, Complete, Completed, JobEntry,
  LocalReleased, QueueEmpty, Release,
}

fn string_value(value: String) -> Json {
  json.string(value)
}

fn ack(
  state: ordered_collection_kernel.OrderedState,
  operation: OrderedOperation,
  author: Int,
) -> #(
  ordered_collection_kernel.OrderedState,
  List(OrderedEvent),
  Option(AcquireOutcome),
) {
  ordered_collection_kernel.ack_local(state, operation, author)
}

pub fn new_state_is_empty_test() -> Nil {
  let state = ordered_collection_kernel.new()
  ordered_collection_kernel.size(state) |> expect.to_equal(0)
  ordered_collection_kernel.summary_queue(state) |> expect.to_equal([])
  ordered_collection_kernel.summary_jobs(state) |> expect.to_equal([])
}

pub fn detached_add_then_acquire_returns_value_at_sequence_number_zero_test() -> Nil {
  let #(state, add_events) =
    ordered_collection_kernel.add_detached(
      ordered_collection_kernel.new(),
      string_value("A"),
    )
  add_events |> expect.to_equal([Added(string_value("A"), True, True)])

  let #(state, acquire_events, outcome) =
    ordered_collection_kernel.acquire_detached(state, "a1")
  acquire_events |> expect.to_equal([Acquired(string_value("A"), None, True)])
  outcome |> expect.to_equal(AcquiredItem("a1", string_value("A")))
  ordered_collection_kernel.summary_queue(state) |> expect.to_equal([])
  ordered_collection_kernel.summary_jobs(state)
  |> expect.to_equal([#("a1", JobEntry(string_value("A"), None))])
}

pub fn detached_acquire_on_empty_resolves_queue_empty_test() -> Nil {
  let #(state, events, outcome) =
    ordered_collection_kernel.acquire_detached(
      ordered_collection_kernel.new(),
      "a1",
    )
  events |> expect.to_equal([])
  outcome |> expect.to_equal(QueueEmpty)
  ordered_collection_kernel.summary_queue(state) |> expect.to_equal([])
  ordered_collection_kernel.summary_jobs(state) |> expect.to_equal([])
}

pub fn summary_flushes_unattached_acquisitions_back_to_queue_test() -> Nil {
  let #(state, _) =
    ordered_collection_kernel.add_detached(
      ordered_collection_kernel.new(),
      string_value("A"),
    )
  let #(state, _, _) = ordered_collection_kernel.acquire_detached(state, "a1")
  let #(state, events) = ordered_collection_kernel.remove_client(state, None)

  events |> expect.to_equal([Added(string_value("A"), False, False)])
  ordered_collection_kernel.summary_queue(state)
  |> expect.to_equal([string_value("A")])
  ordered_collection_kernel.summary_jobs(state) |> expect.to_equal([])
}

pub fn attached_submit_is_not_optimistic_test() -> Nil {
  let state = ordered_collection_kernel.new()
  let operation = ordered_collection_kernel.add(state, string_value("A"))

  operation |> expect.to_equal(Add(string_value("A")))
  ordered_collection_kernel.summary_queue(state) |> expect.to_equal([])
}

pub fn add_and_acquire_ordering_follows_sequence_order_test() -> Nil {
  let state_a = ordered_collection_kernel.new()
  let state_b = ordered_collection_kernel.new()
  let operation_a = ordered_collection_kernel.add(state_a, string_value("A"))
  let operation_b = ordered_collection_kernel.add(state_b, string_value("B"))

  let #(state_a, _, _) = ack(state_a, operation_a, 1)
  let #(state_a, _) =
    ordered_collection_kernel.apply_remote(state_a, operation_b, 2)
  let #(state_b, _) =
    ordered_collection_kernel.apply_remote(state_b, operation_a, 1)
  let #(state_b, _, _) = ack(state_b, operation_b, 2)

  let acquire_a = ordered_collection_kernel.acquire("a1")
  let acquire_b = ordered_collection_kernel.acquire("b1")
  let assert #(state_a, _, Some(outcome_a)) = ack(state_a, acquire_a, 1)
  outcome_a |> expect.to_equal(AcquiredItem("a1", string_value("A")))
  let #(state_a, _) =
    ordered_collection_kernel.apply_remote(state_a, acquire_b, 2)

  let #(state_b, _) =
    ordered_collection_kernel.apply_remote(state_b, acquire_a, 1)
  let assert #(state_b, _, Some(outcome_b)) = ack(state_b, acquire_b, 2)
  outcome_b |> expect.to_equal(AcquiredItem("b1", string_value("B")))

  ordered_collection_kernel.summary_queue(state_a) |> expect.to_equal([])
  ordered_collection_kernel.summary_queue(state_b) |> expect.to_equal([])
  ordered_collection_kernel.summary_jobs(state_a)
  |> expect.to_equal([
    #("a1", JobEntry(string_value("A"), Some(1))),
    #("b1", JobEntry(string_value("B"), Some(2))),
  ])
  ordered_collection_kernel.summary_jobs(state_b)
  |> expect.to_equal(ordered_collection_kernel.summary_jobs(state_a))
}

pub fn racing_acquires_on_one_item_first_sequence_wins_test() -> Nil {
  let #(state_a, _) =
    ordered_collection_kernel.apply_add(
      ordered_collection_kernel.new(),
      string_value("A"),
    )
  let #(state_b, _) =
    ordered_collection_kernel.apply_add(
      ordered_collection_kernel.new(),
      string_value("A"),
    )

  let operation_a = Acquire("a1")
  let operation_b = Acquire("b1")
  let assert #(state_a, _, Some(outcome_a)) = ack(state_a, operation_a, 1)
  outcome_a |> expect.to_equal(AcquiredItem("a1", string_value("A")))
  let #(state_a, _) =
    ordered_collection_kernel.apply_remote(state_a, operation_b, 2)

  let #(state_b, _) =
    ordered_collection_kernel.apply_remote(state_b, operation_a, 1)
  let assert #(state_b, _, Some(outcome_b)) = ack(state_b, operation_b, 2)
  outcome_b |> expect.to_equal(QueueEmpty)

  ordered_collection_kernel.summary_jobs(state_a)
  |> expect.to_equal([#("a1", JobEntry(string_value("A"), Some(1)))])
  ordered_collection_kernel.summary_jobs(state_b)
  |> expect.to_equal(ordered_collection_kernel.summary_jobs(state_a))
}

pub fn acquire_complete_drops_item_test() -> Nil {
  let #(state, _) =
    ordered_collection_kernel.apply_add(
      ordered_collection_kernel.new(),
      string_value("A"),
    )
  let assert #(state, _, Some(outcome)) = ack(state, Acquire("a1"), 1)
  outcome |> expect.to_equal(AcquiredItem("a1", string_value("A")))
  let #(state, events, outcome) = ack(state, Complete("a1"), 1)

  outcome |> expect.to_equal(None)
  events |> expect.to_equal([Completed(string_value("A"), True)])
  ordered_collection_kernel.summary_queue(state) |> expect.to_equal([])
  ordered_collection_kernel.summary_jobs(state) |> expect.to_equal([])
}

pub fn acquire_release_returns_item_to_back_test() -> Nil {
  let #(state, _) =
    ordered_collection_kernel.apply_add(
      ordered_collection_kernel.new(),
      string_value("A"),
    )
  let #(state, _) =
    ordered_collection_kernel.apply_add(state, string_value("B"))
  let assert #(state, _, Some(_)) = ack(state, Acquire("a1"), 1)
  let #(state, events, _) = ack(state, Release("a1"), 1)

  events |> expect.to_equal([Added(string_value("A"), False, True)])
  ordered_collection_kernel.summary_queue(state)
  |> expect.to_equal([string_value("B"), string_value("A")])
  ordered_collection_kernel.summary_jobs(state) |> expect.to_equal([])
}

pub fn complete_and_release_missing_jobs_are_noops_test() -> Nil {
  let state = ordered_collection_kernel.new()
  let #(state, complete_events) =
    ordered_collection_kernel.apply_complete(state, "missing")
  let #(state, release_events) =
    ordered_collection_kernel.apply_release(state, "missing")

  complete_events |> expect.to_equal([])
  release_events |> expect.to_equal([])
  state |> expect.to_equal(ordered_collection_kernel.new())
}

pub fn remove_client_rereleases_owned_jobs_in_deterministic_order_test() -> Nil {
  let state =
    ordered_collection_kernel.from_summary([], [
      #("z", JobEntry(string_value("Z"), Some(1))),
      #("a", JobEntry(string_value("A"), Some(1))),
      #("m", JobEntry(string_value("M"), Some(2))),
    ])
  let #(state, events) = ordered_collection_kernel.remove_client(state, Some(1))

  events
  |> expect.to_equal([
    Added(string_value("A"), False, False),
    Added(string_value("Z"), False, False),
  ])
  ordered_collection_kernel.summary_queue(state)
  |> expect.to_equal([string_value("A"), string_value("Z")])
  ordered_collection_kernel.summary_jobs(state)
  |> expect.to_equal([#("m", JobEntry(string_value("M"), Some(2)))])
}

pub fn rereleased_item_can_be_acquired_and_departed_complete_is_noop_test() -> Nil {
  let #(state, _) =
    ordered_collection_kernel.apply_add(
      ordered_collection_kernel.new(),
      string_value("A"),
    )
  let assert #(state, _, Some(_)) = ack(state, Acquire("a1"), 1)
  let #(state, _) = ordered_collection_kernel.remove_client(state, Some(1))
  let #(state, complete_events) =
    ordered_collection_kernel.apply_remote(state, Complete("a1"), 1)
  let assert #(state, _, Some(outcome)) = ack(state, Acquire("b1"), 2)

  complete_events |> expect.to_equal([])
  outcome |> expect.to_equal(AcquiredItem("b1", string_value("A")))
  ordered_collection_kernel.summary_jobs(state)
  |> expect.to_equal([#("b1", JobEntry(string_value("A"), Some(2)))])
}

pub fn disconnect_notify_emits_local_release_without_state_change_test() -> Nil {
  let state =
    ordered_collection_kernel.from_summary([string_value("Q")], [
      #("a1", JobEntry(string_value("A"), Some(1))),
      #("b1", JobEntry(string_value("B"), Some(2))),
    ])
  let events = ordered_collection_kernel.on_disconnect_notify(state, Some(1))

  events |> expect.to_equal([LocalReleased(string_value("A"), False)])
  ordered_collection_kernel.summary_queue(state)
  |> expect.to_equal([string_value("Q")])
  ordered_collection_kernel.summary_jobs(state)
  |> expect.to_equal([
    #("a1", JobEntry(string_value("A"), Some(1))),
    #("b1", JobEntry(string_value("B"), Some(2))),
  ])
}

pub fn rollback_local_acquire_resolves_empty_and_leaves_queue_intact_test() -> Nil {
  let state = ordered_collection_kernel.from_summary([string_value("A")], [])
  let #(after, outcome) =
    ordered_collection_kernel.rollback(state, Acquire("a1"))

  outcome |> expect.to_equal(QueueEmpty)
  after |> expect.to_equal(state)
}

pub fn stashed_operation_returns_operation_verbatim_and_applies_normally_test() -> Nil {
  let operation = Add(string_value("A"))
  let #(state, resubmit) =
    ordered_collection_kernel.apply_stashed_operation(
      ordered_collection_kernel.new(),
      operation,
    )

  resubmit |> expect.to_equal(operation)
  let #(state, _, _) = ack(state, resubmit, 1)
  ordered_collection_kernel.summary_queue(state)
  |> expect.to_equal([string_value("A")])
}

pub fn summary_round_trips_queue_order_jobs_and_json_null_test() -> Nil {
  let original =
    ordered_collection_kernel.from_summary([string_value("A"), json.null()], [
      #("b", JobEntry(string_value("B"), Some(2))),
      #("a", JobEntry(json.null(), Some(1))),
    ])
  let queue = ordered_collection_kernel.summary_queue(original)
  let jobs = ordered_collection_kernel.summary_jobs(original)
  let loaded = ordered_collection_kernel.from_summary(queue, jobs)

  queue |> expect.to_equal([string_value("A"), json.null()])
  jobs
  |> expect.to_equal([
    #("a", JobEntry(json.null(), Some(1))),
    #("b", JobEntry(string_value("B"), Some(2))),
  ])
  ordered_collection_kernel.summary_queue(loaded) |> expect.to_equal(queue)
  ordered_collection_kernel.summary_jobs(loaded) |> expect.to_equal(jobs)
}

pub fn post_load_acquire_and_complete_work_test() -> Nil {
  let state = ordered_collection_kernel.from_summary([string_value("A")], [])
  let assert #(state, _, Some(outcome)) = ack(state, Acquire("a1"), 1)
  let #(state, events, _) = ack(state, Complete("a1"), 1)

  outcome |> expect.to_equal(AcquiredItem("a1", string_value("A")))
  events |> expect.to_equal([Completed(string_value("A"), True)])
  ordered_collection_kernel.summary_queue(state) |> expect.to_equal([])
  ordered_collection_kernel.summary_jobs(state) |> expect.to_equal([])
}
