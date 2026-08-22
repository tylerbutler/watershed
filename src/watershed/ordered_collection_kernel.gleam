//// Pure port of FluidFramework's ConsensusOrderedCollection queue semantics.
////
//// The collection is not optimistic. An attached add, acquire, complete, or
//// release changes the committed state only when its op sequences.
////
//// An acquire moves an item from the FIFO queue into job tracking. A complete
//// or a release accepts a missing entry, because a sequenced leave can already
//// have released that job.

import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type OrderedState {
  OrderedState(
    /// FIFO queue. The head is the front, which is the next item to remove.
    queue: List(Json),
    /// acquireId to held item. The owner is the client id that acquired the
    /// item, or `None` for a local acquisition on an unattached collection.
    jobs: Dict(String, JobEntry),
  )
}

pub type JobEntry {
  JobEntry(value: Json, owner: Option(Int))
}

pub type OrderedOp {
  Add(value: Json)
  Acquire(acquire_id: String)
  Complete(acquire_id: String)
  Release(acquire_id: String)
}

pub type OrderedEvent {
  /// `newly_added` separates a new add from a release that returns an item to
  /// the queue.
  Added(value: Json, newly_added: Bool, local: Bool)
  Acquired(value: Json, owner: Option(Int), local: Bool)
  Completed(value: Json, local: Bool)
  /// A notification only. The kernel releases a locally held item when the
  /// leave sequences. This event changes no state.
  LocalReleased(value: Json, intentional: Bool)
}

pub type AcquireOutcome {
  AcquiredItem(acquire_id: String, value: Json)
  QueueEmpty
  /// The kernel never produces this event. The runtime resolves an acquire
  /// that is still pending with `Aborted` when the document closes before the
  /// op sequences.
  Aborted
}

pub fn new() -> OrderedState {
  OrderedState(queue: [], jobs: dict.new())
}

pub fn from_summary(
  queue: List(Json),
  jobs: List(#(String, JobEntry)),
) -> OrderedState {
  OrderedState(queue: queue, jobs: jobs_to_dict(jobs))
}

pub fn summary_queue(state: OrderedState) -> List(Json) {
  state.queue
}

pub fn summary_jobs(state: OrderedState) -> List(#(String, JobEntry)) {
  sorted_jobs(state)
}

pub fn size(state: OrderedState) -> Int {
  list.length(state.queue)
}

pub fn add(_state: OrderedState, value: Json) -> OrderedOp {
  Add(value)
}

pub fn acquire(acquire_id: String) -> OrderedOp {
  Acquire(acquire_id)
}

pub fn complete(acquire_id: String) -> OrderedOp {
  Complete(acquire_id)
}

pub fn release(acquire_id: String) -> OrderedOp {
  Release(acquire_id)
}

pub fn add_detached(
  state: OrderedState,
  value: Json,
) -> #(OrderedState, List(OrderedEvent)) {
  apply_add_core(state, value, True, True)
}

pub fn acquire_detached(
  state: OrderedState,
  acquire_id: String,
) -> #(OrderedState, List(OrderedEvent), AcquireOutcome) {
  ack_local_acquire(state, acquire_id, None)
}

pub fn apply_add(
  state: OrderedState,
  value: Json,
) -> #(OrderedState, List(OrderedEvent)) {
  apply_add_core(state, value, True, False)
}

pub fn apply_acquire(
  state: OrderedState,
  acquire_id: String,
  author: Option(Int),
) -> #(OrderedState, List(OrderedEvent), Option(Json)) {
  apply_acquire_core(state, acquire_id, author, False)
}

pub fn apply_complete(
  state: OrderedState,
  acquire_id: String,
) -> #(OrderedState, List(OrderedEvent)) {
  apply_complete_core(state, acquire_id, False)
}

pub fn apply_release(
  state: OrderedState,
  acquire_id: String,
) -> #(OrderedState, List(OrderedEvent)) {
  apply_release_core(state, acquire_id, False)
}

pub fn apply_remote(
  state: OrderedState,
  op: OrderedOp,
  author: Int,
) -> #(OrderedState, List(OrderedEvent)) {
  case op {
    Add(value) -> apply_add_core(state, value, True, False)
    Acquire(acquire_id) -> {
      let #(state, events, _) =
        apply_acquire_core(state, acquire_id, Some(author), False)
      #(state, events)
    }
    Complete(acquire_id) -> apply_complete_core(state, acquire_id, False)
    Release(acquire_id) -> apply_release_core(state, acquire_id, False)
  }
}

pub fn ack_local(
  state: OrderedState,
  op: OrderedOp,
  author: Int,
) -> #(OrderedState, List(OrderedEvent), Option(AcquireOutcome)) {
  case op {
    Add(value) -> {
      let #(state, events) = apply_add_core(state, value, True, True)
      #(state, events, None)
    }
    Acquire(acquire_id) -> {
      let #(state, events, outcome) =
        ack_local_acquire(state, acquire_id, Some(author))
      #(state, events, Some(outcome))
    }
    Complete(acquire_id) -> {
      let #(state, events) = apply_complete_core(state, acquire_id, True)
      #(state, events, None)
    }
    Release(acquire_id) -> {
      let #(state, events) = apply_release_core(state, acquire_id, True)
      #(state, events, None)
    }
  }
}

pub fn ack_local_acquire(
  state: OrderedState,
  acquire_id: String,
  author: Option(Int),
) -> #(OrderedState, List(OrderedEvent), AcquireOutcome) {
  let #(state, events, value) =
    apply_acquire_core(state, acquire_id, author, True)
  let outcome = case value {
    Some(value) -> AcquiredItem(acquire_id, value)
    None -> QueueEmpty
  }
  #(state, events, outcome)
}

pub fn remove_client(
  state: OrderedState,
  owner: Option(Int),
) -> #(OrderedState, List(OrderedEvent)) {
  let #(jobs, returned_values) =
    sorted_jobs(state)
    |> list.fold(#(state.jobs, []), fn(acc, entry) {
      let #(jobs, returned_values) = acc
      let #(acquire_id, JobEntry(value, job_owner)) = entry
      case job_owner == owner {
        True -> #(
          dict.delete(jobs, acquire_id),
          list.append(returned_values, [value]),
        )
        False -> acc
      }
    })

  let queue = list.append(state.queue, returned_values)
  let events =
    returned_values
    |> list.map(fn(value) { Added(value, False, False) })
  #(OrderedState(queue: queue, jobs: jobs), events)
}

pub fn on_disconnect_notify(
  state: OrderedState,
  owner: Option(Int),
) -> List(OrderedEvent) {
  sorted_jobs(state)
  |> list.filter_map(fn(entry) {
    let #(_, JobEntry(value, job_owner)) = entry
    case job_owner == owner {
      True -> Ok(LocalReleased(value, False))
      False -> Error(Nil)
    }
  })
}

pub fn rollback(
  state: OrderedState,
  _op: OrderedOp,
) -> #(OrderedState, AcquireOutcome) {
  #(state, QueueEmpty)
}

pub fn apply_stashed_op(
  state: OrderedState,
  op: OrderedOp,
) -> #(OrderedState, OrderedOp) {
  #(state, op)
}

fn apply_add_core(
  state: OrderedState,
  value: Json,
  newly_added: Bool,
  local: Bool,
) -> #(OrderedState, List(OrderedEvent)) {
  let state = OrderedState(..state, queue: list.append(state.queue, [value]))
  #(state, [Added(value, newly_added, local)])
}

fn apply_acquire_core(
  state: OrderedState,
  acquire_id: String,
  author: Option(Int),
  local: Bool,
) -> #(OrderedState, List(OrderedEvent), Option(Json)) {
  case state.queue {
    [] -> #(state, [], None)
    [value, ..rest] -> {
      let state =
        OrderedState(
          queue: rest,
          jobs: dict.insert(state.jobs, acquire_id, JobEntry(value, author)),
        )
      #(state, [Acquired(value, author, local)], Some(value))
    }
  }
}

fn apply_complete_core(
  state: OrderedState,
  acquire_id: String,
  local: Bool,
) -> #(OrderedState, List(OrderedEvent)) {
  case dict.get(state.jobs, acquire_id) {
    Error(_) -> #(state, [])
    Ok(JobEntry(value, _)) -> {
      let state =
        OrderedState(..state, jobs: dict.delete(state.jobs, acquire_id))
      #(state, [Completed(value, local)])
    }
  }
}

fn apply_release_core(
  state: OrderedState,
  acquire_id: String,
  local: Bool,
) -> #(OrderedState, List(OrderedEvent)) {
  case dict.get(state.jobs, acquire_id) {
    Error(_) -> #(state, [])
    Ok(JobEntry(value, _)) -> {
      let state =
        OrderedState(..state, jobs: dict.delete(state.jobs, acquire_id))
      apply_add_core(state, value, False, local)
    }
  }
}

fn sorted_jobs(state: OrderedState) -> List(#(String, JobEntry)) {
  dict.to_list(state.jobs)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

fn jobs_to_dict(jobs: List(#(String, JobEntry))) -> Dict(String, JobEntry) {
  list.fold(jobs, dict.new(), fn(acc, entry) {
    let #(acquire_id, job) = entry
    dict.insert(acc, acquire_id, job)
  })
}
