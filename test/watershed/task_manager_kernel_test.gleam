//// Unit suite for `task_manager_kernel`, covering the pure consensus queue
//// semantics from Fluid TaskManager.

import gleam/option.{type Option, None, Some}
import startest/expect
import watershed/task_manager_kernel.{
  type PendingOp, type TaskManagerError, type TaskManagerEvent,
  type TaskManagerOp, Abandon, Abandoned, Assigned, AssignedNow, Complete,
  Completed, Lost, NotAssigned, PendingOp, PendingVolunteer, QueueChanged,
  RolledBack, UnexpectedAck, UnexpectedResubmit, UnexpectedRollback, Volunteer,
  Waiting,
}

fn ack(
  state: task_manager_kernel.TaskManagerState,
  op: TaskManagerOp,
  author: Int,
  message_id: Int,
) -> #(task_manager_kernel.TaskManagerState, List(TaskManagerEvent)) {
  case task_manager_kernel.ack_local(state, op, author, message_id, [1, 2, 3]) {
    Ok(pair) -> pair
    Error(_) -> panic as "expected ack_local to succeed"
  }
}

fn submitted(
  triple: #(task_manager_kernel.TaskManagerState, Option(TaskManagerOp), a),
) -> #(task_manager_kernel.TaskManagerState, TaskManagerOp, a) {
  let #(state, op, outcome) = triple
  case op {
    Some(op) -> #(state, op, outcome)
    None -> panic as "expected op to be submitted"
  }
}

fn completed(
  result: Result(
    #(task_manager_kernel.TaskManagerState, TaskManagerOp),
    TaskManagerError,
  ),
) -> #(task_manager_kernel.TaskManagerState, TaskManagerOp) {
  case result {
    Ok(pair) -> pair
    Error(_) -> panic as "expected complete to succeed"
  }
}

fn resubmitted(
  result: Result(
    #(
      task_manager_kernel.TaskManagerState,
      Option(TaskManagerOp),
      Option(PendingOp),
    ),
    TaskManagerError,
  ),
) -> #(
  task_manager_kernel.TaskManagerState,
  Option(TaskManagerOp),
  Option(PendingOp),
) {
  case result {
    Ok(triple) -> triple
    Error(_) -> panic as "expected resubmit to succeed"
  }
}

pub fn new_state_is_empty_test() {
  let state = task_manager_kernel.new()

  task_manager_kernel.summary_queues(state) |> expect.to_equal([])
  task_manager_kernel.assigned(state, "task", 1, True) |> expect.to_be_false()
  task_manager_kernel.queued(state, "task", 1, True) |> expect.to_be_false()
  task_manager_kernel.queued_optimistically(state, "task", 1)
  |> expect.to_be_false()
}

pub fn volunteer_is_pending_until_local_ack_test() {
  let #(state, op, outcome) =
    submitted(task_manager_kernel.volunteer(
      task_manager_kernel.new(),
      "task",
      1,
      10,
    ))

  op |> expect.to_equal(Volunteer("task"))
  outcome |> expect.to_equal(Waiting)
  task_manager_kernel.summary_queues(state) |> expect.to_equal([])
  task_manager_kernel.queued_optimistically(state, "task", 1)
  |> expect.to_be_true()

  let #(state, events) = ack(state, op, 1, 10)
  events
  |> expect.to_equal([
    QueueChanged("task", None, Some(1)),
    Assigned("task"),
  ])
  task_manager_kernel.summary_queues(state) |> expect.to_equal([#("task", [1])])
  task_manager_kernel.assigned(state, "task", 1, True) |> expect.to_be_true()
}

pub fn two_clients_queue_fifo_and_abandon_promotes_waiter_test() {
  let #(state, events) =
    task_manager_kernel.apply_remote(
      task_manager_kernel.new(),
      Volunteer("task"),
      1,
      [1, 2],
    )
  events |> expect.to_equal([QueueChanged("task", None, Some(1))])

  let #(state, events) =
    task_manager_kernel.apply_remote(state, Volunteer("task"), 2, [1, 2])
  events |> expect.to_equal([])
  task_manager_kernel.summary_queues(state)
  |> expect.to_equal([#("task", [1, 2])])

  let #(state, events) =
    task_manager_kernel.apply_remote(state, Abandon("task"), 1, [1, 2])
  events |> expect.to_equal([QueueChanged("task", Some(1), Some(2))])
  task_manager_kernel.summary_queues(state) |> expect.to_equal([#("task", [2])])
}

pub fn duplicate_remote_volunteer_does_not_duplicate_client_test() {
  let #(state, _) =
    task_manager_kernel.apply_remote(
      task_manager_kernel.new(),
      Volunteer("task"),
      1,
      [1],
    )
  let #(state, events) =
    task_manager_kernel.apply_remote(state, Volunteer("task"), 1, [1])

  events |> expect.to_equal([])
  task_manager_kernel.summary_queues(state) |> expect.to_equal([#("task", [1])])
}

pub fn second_volunteer_while_pending_sends_no_second_op_test() {
  let #(state, op, _) =
    submitted(task_manager_kernel.volunteer(
      task_manager_kernel.new(),
      "task",
      1,
      10,
    ))

  op |> expect.to_equal(Volunteer("task"))
  let #(state, second_op, outcome) =
    task_manager_kernel.volunteer(state, "task", 1, 11)

  second_op |> expect.to_equal(None)
  outcome |> expect.to_equal(Waiting)
  task_manager_kernel.summary_queues(state) |> expect.to_equal([])
}

pub fn abandon_after_pending_volunteer_flips_optimistic_membership_test() {
  let #(state, _, _) =
    submitted(task_manager_kernel.volunteer(
      task_manager_kernel.new(),
      "task",
      1,
      10,
    ))
  let #(state, abandon_op, events) =
    task_manager_kernel.abandon(state, "task", 1, 11)

  abandon_op |> expect.to_equal(Some(Abandon("task")))
  events |> expect.to_equal([Abandoned("task")])
  task_manager_kernel.queued_optimistically(state, "task", 1)
  |> expect.to_be_false()
}

pub fn abandon_then_immediate_reacquire_follows_pending_order_test() {
  let state = task_manager_kernel.from_summary([#("task", [1])])
  let #(state, abandon_op, _) =
    task_manager_kernel.abandon(state, "task", 1, 10)
  abandon_op |> expect.to_equal(Some(Abandon("task")))

  let #(state, volunteer_op, _) =
    task_manager_kernel.volunteer(state, "task", 1, 11)
  volunteer_op |> expect.to_equal(Some(Volunteer("task")))

  let #(state, abandon_events) = ack(state, Abandon("task"), 1, 10)
  abandon_events
  |> expect.to_equal([
    QueueChanged("task", Some(1), None),
    Abandoned("task"),
  ])
  let #(state, volunteer_events) = ack(state, Volunteer("task"), 1, 11)
  volunteer_events
  |> expect.to_equal([
    QueueChanged("task", None, Some(1)),
    Assigned("task"),
  ])
  task_manager_kernel.summary_queues(state) |> expect.to_equal([#("task", [1])])
}

pub fn complete_requires_assignment_and_clears_waiters_test() {
  let unassigned = task_manager_kernel.from_summary([#("task", [2])])
  case task_manager_kernel.complete(unassigned, "task", 1, 10) {
    Error(NotAssigned("task")) -> Nil
    _ -> panic as "expected NotAssigned"
  }

  let state = task_manager_kernel.from_summary([#("task", [1, 2])])
  let #(state, op) =
    completed(task_manager_kernel.complete(state, "task", 1, 10))
  op |> expect.to_equal(Complete("task"))
  let #(state, events) = ack(state, op, 1, 10)

  events
  |> expect.to_equal([
    QueueChanged("task", Some(1), None),
    Completed("task"),
  ])
  task_manager_kernel.summary_queues(state) |> expect.to_equal([])
}

pub fn disconnected_reads_return_false_test() {
  let state = task_manager_kernel.from_summary([#("task", [1])])

  task_manager_kernel.assigned(state, "task", 1, False) |> expect.to_be_false()
  task_manager_kernel.queued(state, "task", 1, False) |> expect.to_be_false()
  task_manager_kernel.assigned(state, "task", 1, True) |> expect.to_be_true()
  task_manager_kernel.queued(state, "task", 1, True) |> expect.to_be_true()
}

pub fn remove_client_updates_every_queue_in_task_order_test() {
  let state =
    task_manager_kernel.from_summary([
      #("z", [1, 3]),
      #("a", [2, 1]),
      #("m", [1]),
    ])
  let #(state, events) = task_manager_kernel.remove_client(state, 1)

  events
  |> expect.to_equal([
    QueueChanged("m", Some(1), None),
    QueueChanged("z", Some(1), Some(3)),
  ])
  task_manager_kernel.summary_queues(state)
  |> expect.to_equal([#("a", [2]), #("z", [3])])
}

pub fn local_disconnect_emits_lost_for_assigned_tasks_and_removes_self_test() {
  let state =
    task_manager_kernel.from_summary([
      #("a", [1, 2]),
      #("b", [2, 1]),
      #("c", [1]),
    ])
  let #(state, events) = task_manager_kernel.on_disconnect(state, 1)

  events
  |> expect.to_equal([
    Lost("a"),
    QueueChanged("a", Some(1), Some(2)),
    Lost("c"),
    QueueChanged("c", Some(1), None),
  ])
  task_manager_kernel.summary_queues(state)
  |> expect.to_equal([#("a", [2]), #("b", [2])])
}

pub fn detached_operations_apply_immediately_test() {
  let #(state, events, outcome) =
    task_manager_kernel.volunteer_detached(task_manager_kernel.new(), "task", 1)
  outcome |> expect.to_equal(AssignedNow)
  events
  |> expect.to_equal([
    QueueChanged("task", None, Some(1)),
    Assigned("task"),
  ])

  let #(state, events) = task_manager_kernel.abandon_detached(state, "task", 1)
  events
  |> expect.to_equal([
    QueueChanged("task", Some(1), None),
    Abandoned("task"),
  ])

  let #(state, _, _) = task_manager_kernel.volunteer_detached(state, "task", 1)
  let #(state, events) = task_manager_kernel.complete_detached(state, "task")
  events
  |> expect.to_equal([
    QueueChanged("task", Some(1), None),
    Completed("task"),
  ])
  task_manager_kernel.summary_queues(state) |> expect.to_equal([])
}

pub fn placeholder_replacement_preserves_assignment_and_avoids_duplicates_test() {
  let state =
    task_manager_kernel.from_summary([
      #("a", [-1, 2]),
      #("b", [2, -1]),
    ])
  let state = task_manager_kernel.replace_placeholder(state, -1, 2)

  task_manager_kernel.summary_queues(state)
  |> expect.to_equal([#("a", [2]), #("b", [2])])
}

pub fn scrub_not_in_quorum_removes_missing_clients_test() {
  let state =
    task_manager_kernel.from_summary([
      #("a", [1, 2]),
      #("b", [3]),
    ])
  let #(state, events) = task_manager_kernel.scrub_not_in_quorum(state, [2])

  events
  |> expect.to_equal([
    QueueChanged("a", Some(1), Some(2)),
    QueueChanged("b", Some(3), None),
  ])
  task_manager_kernel.summary_queues(state) |> expect.to_equal([#("a", [2])])
}

pub fn summary_round_trip_sorts_tasks_and_drops_pending_test() {
  let #(state, _, _) =
    submitted(task_manager_kernel.volunteer(
      task_manager_kernel.from_summary([#("z", [3]), #("a", [1])]),
      "pending",
      2,
      10,
    ))
  let summary = task_manager_kernel.summary_queues(state)
  let loaded = task_manager_kernel.from_summary(summary)

  summary |> expect.to_equal([#("a", [1]), #("z", [3])])
  task_manager_kernel.summary_queues(loaded) |> expect.to_equal(summary)
  task_manager_kernel.queued_optimistically(loaded, "pending", 2)
  |> expect.to_be_false()
}

pub fn rollback_pops_latest_pending_and_emits_rolled_back_test() {
  let #(state, _, _) =
    submitted(task_manager_kernel.volunteer(
      task_manager_kernel.new(),
      "task",
      1,
      10,
    ))
  let #(state, _, _) =
    submitted(task_manager_kernel.volunteer(state, "other", 1, 20))
  let #(state, events) = case
    task_manager_kernel.rollback(state, Volunteer("other"), 20)
  {
    Ok(pair) -> pair
    Error(_) -> panic as "expected rollback to succeed"
  }

  events |> expect.to_equal([RolledBack("other")])
  task_manager_kernel.queued_optimistically(state, "task", 1)
  |> expect.to_be_true()
  task_manager_kernel.queued_optimistically(state, "other", 1)
  |> expect.to_be_false()
}

pub fn rollback_requires_latest_pending_match_test() {
  let #(state, _, _) =
    submitted(task_manager_kernel.volunteer(
      task_manager_kernel.new(),
      "task",
      1,
      10,
    ))
  case task_manager_kernel.rollback(state, Volunteer("task"), 99) {
    Error(UnexpectedRollback(Volunteer("task"), _)) -> Nil
    _ -> panic as "expected UnexpectedRollback"
  }
}

pub fn resubmit_reissues_volunteer_unless_superseded_by_abandon_test() {
  let #(state, _, _) =
    submitted(task_manager_kernel.volunteer(
      task_manager_kernel.new(),
      "task",
      1,
      10,
    ))
  let #(state, op, pending) =
    resubmitted(task_manager_kernel.resubmit(state, Volunteer("task"), 10, 11))

  op |> expect.to_equal(Some(Volunteer("task")))
  pending |> expect.to_equal(Some(PendingOp(PendingVolunteer, 11)))
  task_manager_kernel.queued_optimistically(state, "task", 1)
  |> expect.to_be_true()

  let #(state, _, _) =
    submitted(task_manager_kernel.volunteer(
      task_manager_kernel.new(),
      "task",
      1,
      21,
    ))
  let #(state, _, _) = task_manager_kernel.abandon(state, "task", 1, 22)
  let #(_, op, pending) =
    resubmitted(task_manager_kernel.resubmit(state, Volunteer("task"), 21, 23))

  op |> expect.to_equal(None)
  pending |> expect.to_equal(None)
}

pub fn resubmit_and_ack_are_strict_about_matching_pending_ops_test() {
  let state = task_manager_kernel.new()

  case task_manager_kernel.resubmit(state, Volunteer("task"), 10, 11) {
    Error(UnexpectedResubmit(Volunteer("task"), _)) -> Nil
    _ -> panic as "expected UnexpectedResubmit"
  }

  case task_manager_kernel.ack_local(state, Volunteer("task"), 1, 10, [1]) {
    Error(UnexpectedAck(Volunteer("task"), _)) -> Nil
    _ -> panic as "expected UnexpectedAck"
  }
}

pub fn stashed_ops_are_ignored_test() {
  let #(state, op) =
    task_manager_kernel.apply_stashed_op(
      task_manager_kernel.new(),
      Volunteer("task"),
    )

  op |> expect.to_equal(None)
  task_manager_kernel.summary_queues(state) |> expect.to_equal([])
}
