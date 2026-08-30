//// The four claims the dispatch board makes, asserted rather than eyeballed
//// in three tabs: a claim race has exactly one winner, a dying worker's job
//// returns to the queue on its own, the dispatcher role passes to the queued
//// backup the same way, and a voluntary release is the graceful twin of the
//// kill. The in-memory `sluice_js` delivers every frame explicitly, so
//// `settle` drains the room before the assertions read it — including the
//// sequenced `"leave"` that `disconnect` fans out to the survivors.

import gleam/json.{type Json}
import gleam/list
import gleam/option.{Some}
import gleeunit/should

import watershed.{type Document, type OrderedCollection, type TaskManager}
import watershed/client_id
import watershed/ordered_collection_kernel.{
  type AcquireOutcome, type OrderedEvent, AcquiredItem, JobEntry,
}
import watershed/sluice_js.{type Sluice}
import watershed/task_manager_kernel.{type TaskManagerEvent}
import watershed/transport_js.{type Cell}

import work_queue_lustre/doc_schema

const role = "dispatcher"

// ── Harness ──────────────────────────────────────────────────────────────────

/// A room with the queue and roles channels seeded on A and resolvable by
/// everyone. The app bootstraps these with `ensure_*` retry loops — right in a
/// browser, wrong here, where delivery is synchronous and deterministic.
fn room(
  name: String,
) -> #(Sluice, Document(doc_schema.Dispatch), Document(doc_schema.Dispatch)) {
  let sluice = sluice_js.start(tenant: "default", document: name)
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)

  let root_a = watershed.root(doc_a)
  let assert Ok(queue) = watershed.create_ordered_collection(doc_a)
  watershed.set(root_a, "queue", watershed.ordered_collection_handle_of(queue))
  let assert Ok(roles) = watershed.create_task_manager(doc_a)
  watershed.set(root_a, "roles", watershed.task_manager_handle_of(roles))
  sluice_js.settle(sluice)

  #(sluice, doc_a, doc_b)
}

fn queue_of(doc: Document(doc_schema.Dispatch)) -> OrderedCollection {
  let assert Ok(handle) = watershed.get(watershed.root(doc), "queue")
  let assert Ok(queue) = watershed.resolve_ordered_collection(doc, handle)
  queue
}

fn roles_of(doc: Document(doc_schema.Dispatch)) -> TaskManager {
  let assert Ok(handle) = watershed.get(watershed.root(doc), "roles")
  let assert Ok(roles) = watershed.resolve_task_manager(doc, handle)
  roles
}

fn int_of(doc: Document(doc_schema.Dispatch)) -> Int {
  let assert Some(id) = watershed.client_id(doc)
  client_id.to_int(id)
}

fn push(cell: Cell(List(a)), item: a) -> Nil {
  transport_js.set_cell(cell, [item, ..transport_js.get_cell(cell)])
}

fn outcome_cell(
  queue: OrderedCollection,
) -> #(Cell(List(AcquireOutcome)), String) {
  let cell = transport_js.new_cell([])
  let acquire_id = watershed.ordered_acquire_with_outcome(queue, push(cell, _))
  #(cell, acquire_id)
}

fn queue_events(queue: OrderedCollection) -> Cell(List(OrderedEvent)) {
  let cell = transport_js.new_cell([])
  watershed.subscribe_ordered_collection(queue, push(cell, _))
  cell
}

fn role_events(roles: TaskManager) -> Cell(List(TaskManagerEvent)) {
  let cell = transport_js.new_cell([])
  watershed.subscribe_task_manager(roles, push(cell, _))
  cell
}

fn job(label: String) -> Json {
  json.object([
    #("id", json.string(label)),
    #("label", json.string(label)),
    #("created_by", json.string("test")),
  ])
}

// ── Claim race ───────────────────────────────────────────────────────────────

/// Two clients race one job in the same sequencing drain: exactly one outcome
/// is `AcquiredItem`, the loser gets `QueueEmpty` (its operation emits no event
/// — the outcome is its only signal), and both replicas agree on who holds the
/// job.
pub fn two_claims_one_job_exactly_one_wins_test() -> Nil {
  let #(sluice, doc_a, doc_b) = room("wq-race")
  let queue_a = queue_of(doc_a)
  let queue_b = queue_of(doc_b)

  watershed.ordered_add(queue_a, job("j1"))
  sluice_js.settle(sluice)

  // Both mint acquire ids synchronously — the id is not the win. The win is
  // decided when the operations sequence, in one drain.
  let #(outcomes_a, _id_a) = outcome_cell(queue_a)
  let #(outcomes_b, _id_b) = outcome_cell(queue_b)
  sluice_js.settle(sluice)

  let a = transport_js.get_cell(outcomes_a)
  let b = transport_js.get_cell(outcomes_b)
  list.length(a) |> should.equal(1)
  list.length(b) |> should.equal(1)
  list.append(a, b)
  |> list.filter(fn(outcome) {
    case outcome {
      AcquiredItem(..) -> True
      ordered_collection_kernel.QueueEmpty
      | ordered_collection_kernel.Aborted -> False
    }
  })
  |> list.length
  |> should.equal(1)

  // Both replicas agree: queue drained, one held job, owned by exactly one of
  // the two clients.
  watershed.ordered_size(queue_a) |> should.equal(Ok(0))
  watershed.ordered_queue(queue_b) |> should.equal([])
  let jobs = watershed.ordered_jobs(queue_a)
  jobs |> should.equal(watershed.ordered_jobs(queue_b))
  let assert [#(_, JobEntry(_, Some(owner)))] = jobs
  { owner == int_of(doc_a) || owner == int_of(doc_b) }
  |> should.be_true()
}

// ── The kill ─────────────────────────────────────────────────────────────────

/// A worker dies mid-job: the server's sequenced `"leave"` re-releases the job
/// to the queue in the surviving replica — as `Added(newly_added: False)`, the
/// signal the board renders "job returned" from — and the survivor can take it
/// over. No client code participates in the recovery.
pub fn held_job_returns_to_queue_when_holder_disconnects_test() -> Nil {
  let #(sluice, doc_a, doc_b) = room("wq-worker-dies")
  let queue_a = queue_of(doc_a)
  let queue_b = queue_of(doc_b)
  let payload = job("doomed")

  watershed.ordered_add(queue_a, payload)
  sluice_js.settle(sluice)

  let events_b = queue_events(queue_b)
  let #(outcomes_a, id_a) = outcome_cell(queue_a)
  sluice_js.settle(sluice)
  transport_js.get_cell(outcomes_a)
  |> should.equal([AcquiredItem(id_a, payload)])
  watershed.ordered_jobs(queue_b)
  |> should.equal([#(id_a, JobEntry(payload, Some(int_of(doc_a))))])

  // The tab holding the job goes away without completing or releasing.
  sluice_js.disconnect(sluice, doc_a)
  sluice_js.settle(sluice)

  transport_js.get_cell(events_b)
  |> list.contains(ordered_collection_kernel.Added(payload, False, False))
  |> should.be_true()
  watershed.ordered_queue(queue_b) |> should.equal([payload])
  watershed.ordered_jobs(queue_b) |> should.equal([])

  // The recovered job is workable, not a tombstone.
  let #(outcomes_b, id_b) = outcome_cell(queue_b)
  sluice_js.settle(sluice)
  transport_js.get_cell(outcomes_b)
  |> should.equal([AcquiredItem(id_b, payload)])
}

/// The dispatcher dies and the queued backup inherits the role. The surviving
/// tab is promoted by a bare `QueueChanged` — **no** `Assigned` event fires on
/// a leave-promotion — which is exactly the signal the app's promotion logic
/// listens for. If the runtime ever starts emitting `Assigned` here, this test
/// says the app's detection has a redundant leg.
pub fn dispatcher_promotion_arrives_as_queue_changed_not_assigned_test() -> Nil {
  let #(sluice, doc_a, doc_b) = room("wq-dispatcher-dies")
  let roles_a = roles_of(doc_a)
  let roles_b = roles_of(doc_b)

  watershed.volunteer_for_task(roles_a, role)
  sluice_js.settle(sluice)

  let events_b = role_events(roles_b)
  watershed.volunteer_for_task(roles_b, role)
  sluice_js.settle(sluice)
  watershed.task_assigned(roles_b, role) |> should.be_false()

  sluice_js.disconnect(sluice, doc_a)
  sluice_js.settle(sluice)

  watershed.task_assigned(roles_b, role) |> should.be_true()
  let events = transport_js.get_cell(events_b)
  events
  |> list.contains(task_manager_kernel.QueueChanged(
    role,
    Some(int_of(doc_a)),
    Some(int_of(doc_b)),
  ))
  |> should.be_true()
  events
  |> list.filter(fn(event) {
    case event {
      task_manager_kernel.Assigned(..) -> True
      task_manager_kernel.QueueChanged(..)
      | task_manager_kernel.Lost(..)
      | task_manager_kernel.Completed(..)
      | task_manager_kernel.Abandoned(..)
      | task_manager_kernel.RolledBack(..) -> False
    }
  })
  |> should.equal([])
}

// ── Release ──────────────────────────────────────────────────────────────────

/// Voluntary release is the graceful twin of the kill: the job returns to the
/// **tail** of the queue as the same `Added(newly_added: False)`, and behind
/// any jobs added meanwhile.
pub fn released_job_returns_to_the_tail_test() -> Nil {
  let #(sluice, doc_a, doc_b) = room("wq-release")
  let queue_a = queue_of(doc_a)
  let queue_b = queue_of(doc_b)
  let first = job("first")
  let second = job("second")

  watershed.ordered_add(queue_a, first)
  watershed.ordered_add(queue_a, second)
  sluice_js.settle(sluice)

  let events_b = queue_events(queue_b)
  let #(outcomes_a, id_a) = outcome_cell(queue_a)
  sluice_js.settle(sluice)
  transport_js.get_cell(outcomes_a)
  |> should.equal([AcquiredItem(id_a, first)])

  watershed.ordered_release(queue_a, id_a)
  sluice_js.settle(sluice)

  transport_js.get_cell(events_b)
  |> list.contains(ordered_collection_kernel.Added(first, False, False))
  |> should.be_true()
  watershed.ordered_queue(queue_b) |> should.equal([second, first])
  watershed.ordered_jobs(queue_b) |> should.equal([])
}
