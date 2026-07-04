//// Pure consensus queue kernel for Fluid TaskManager semantics.
////
//// The kernel owns committed per-task FIFO queues plus the small amount of
//// local pending-op metadata needed for optimistic submit guards, strict local
//// acks, rollback, and resubmit. Promises, subscriptions, read-only checks, and
//// reconnect policy remain runtime-layer concerns.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type TaskManagerState {
  TaskManagerState(
    /// task id -> FIFO client queue; head owns the task.
    queues: Dict(String, List(Int)),
    /// task id -> FIFO local pending ops for this client.
    pending: Dict(String, List(PendingOp)),
  )
}

pub type TaskManagerOp {
  Volunteer(task_id: String)
  Abandon(task_id: String)
  Complete(task_id: String)
}

pub type PendingOp {
  PendingOp(kind: PendingKind, message_id: Int)
}

pub type PendingKind {
  PendingVolunteer
  PendingAbandon
  PendingComplete
}

pub type TaskManagerEvent {
  QueueChanged(
    task_id: String,
    old_assignee: Option(Int),
    new_assignee: Option(Int),
  )
  Assigned(task_id: String)
  Lost(task_id: String)
  Completed(task_id: String)
  Abandoned(task_id: String)
  RolledBack(task_id: String)
}

pub type VolunteerOutcome {
  AssignedNow
  Waiting
  CompletedBeforeAssignment
  AbandonedBeforeAssignment
  DisconnectedBeforeAssignment
  RolledBackBeforeAssignment
}

pub type TaskManagerError {
  NotAssigned(task_id: String)
  UnexpectedAck(op: TaskManagerOp, detail: String)
  UnexpectedRollback(op: TaskManagerOp, detail: String)
  UnexpectedResubmit(op: TaskManagerOp, detail: String)
}

pub fn new() -> TaskManagerState {
  TaskManagerState(queues: dict.new(), pending: dict.new())
}

pub fn from_summary(queues: List(#(String, List(Int)))) -> TaskManagerState {
  let queues =
    queues
    |> list.fold(dict.new(), fn(acc, entry) {
      let #(task_id, queue) = entry
      set_queue(acc, task_id, queue)
    })
  TaskManagerState(queues: queues, pending: dict.new())
}

pub fn summary_queues(state: TaskManagerState) -> List(#(String, List(Int))) {
  sorted_queues(state)
  |> list.filter(fn(entry) {
    let #(_, queue) = entry
    queue != []
  })
}

pub fn assigned(
  state: TaskManagerState,
  task_id: String,
  self_id: Int,
  connected: Bool,
) -> Bool {
  case connected {
    False -> False
    True -> assignee(state, task_id) == Some(self_id)
  }
}

pub fn queued(
  state: TaskManagerState,
  task_id: String,
  self_id: Int,
  connected: Bool,
) -> Bool {
  case connected {
    False -> False
    True -> list.contains(queue_for(state, task_id), self_id)
  }
}

pub fn queued_optimistically(
  state: TaskManagerState,
  task_id: String,
  self_id: Int,
) -> Bool {
  case latest_pending(state, task_id) {
    Some(PendingOp(PendingVolunteer, _)) -> True
    Some(PendingOp(PendingAbandon, _)) -> False
    Some(PendingOp(PendingComplete, _)) -> False
    None -> list.contains(queue_for(state, task_id), self_id)
  }
}

pub fn volunteer(
  state: TaskManagerState,
  task_id: String,
  self_id: Int,
  message_id: Int,
) -> #(TaskManagerState, Option(TaskManagerOp), VolunteerOutcome) {
  case queued_optimistically(state, task_id, self_id) {
    True -> {
      let outcome = case assigned(state, task_id, self_id, True) {
        True -> AssignedNow
        False -> Waiting
      }
      #(state, None, outcome)
    }
    False -> {
      let state =
        add_pending(state, task_id, PendingOp(PendingVolunteer, message_id))
      #(state, Some(Volunteer(task_id)), Waiting)
    }
  }
}

pub fn volunteer_detached(
  state: TaskManagerState,
  task_id: String,
  self_id: Int,
) -> #(TaskManagerState, List(TaskManagerEvent), VolunteerOutcome) {
  let #(state, events) =
    apply_volunteer_core(state, task_id, self_id, [self_id], True)
  let outcome = case assigned(state, task_id, self_id, True) {
    True -> AssignedNow
    False -> Waiting
  }
  #(state, events, outcome)
}

pub fn abandon(
  state: TaskManagerState,
  task_id: String,
  self_id: Int,
  message_id: Int,
) -> #(TaskManagerState, Option(TaskManagerOp), List(TaskManagerEvent)) {
  case queued_optimistically(state, task_id, self_id) {
    False -> #(state, None, [])
    True -> {
      let state =
        add_pending(state, task_id, PendingOp(PendingAbandon, message_id))
      #(state, Some(Abandon(task_id)), [Abandoned(task_id)])
    }
  }
}

pub fn abandon_detached(
  state: TaskManagerState,
  task_id: String,
  self_id: Int,
) -> #(TaskManagerState, List(TaskManagerEvent)) {
  apply_abandon_core(state, task_id, self_id, True)
}

pub fn complete(
  state: TaskManagerState,
  task_id: String,
  self_id: Int,
  message_id: Int,
) -> Result(#(TaskManagerState, TaskManagerOp), TaskManagerError) {
  case assigned(state, task_id, self_id, True) {
    False -> Error(NotAssigned(task_id))
    True -> {
      let state =
        add_pending(state, task_id, PendingOp(PendingComplete, message_id))
      Ok(#(state, Complete(task_id)))
    }
  }
}

pub fn complete_detached(
  state: TaskManagerState,
  task_id: String,
) -> #(TaskManagerState, List(TaskManagerEvent)) {
  apply_complete_core(state, task_id)
}

pub fn apply_remote(
  state: TaskManagerState,
  op: TaskManagerOp,
  author: Int,
  quorum: List(Int),
) -> #(TaskManagerState, List(TaskManagerEvent)) {
  case op {
    Volunteer(task_id) ->
      apply_volunteer_core(state, task_id, author, quorum, False)
    Abandon(task_id) -> apply_abandon_core(state, task_id, author, False)
    Complete(task_id) -> apply_complete_core(state, task_id)
  }
}

pub fn ack_local(
  state: TaskManagerState,
  op: TaskManagerOp,
  author: Int,
  message_id: Int,
  quorum: List(Int),
) -> Result(#(TaskManagerState, List(TaskManagerEvent)), TaskManagerError) {
  let task_id = op_task_id(op)
  let expected = op_pending_kind(op)
  case pop_oldest_pending(state, task_id, expected, message_id) {
    Error(detail) -> Error(UnexpectedAck(op, detail))
    Ok(state) -> {
      let #(state, events) = case op {
        Volunteer(_) ->
          apply_volunteer_core(state, task_id, author, quorum, True)
        Abandon(_) -> apply_abandon_core(state, task_id, author, True)
        Complete(_) -> apply_complete_core(state, task_id)
      }
      Ok(#(state, events))
    }
  }
}

pub fn remove_client(
  state: TaskManagerState,
  client_id: Int,
) -> #(TaskManagerState, List(TaskManagerEvent)) {
  remove_client_with_lost(state, client_id, False)
}

pub fn on_disconnect(
  state: TaskManagerState,
  self_id: Int,
) -> #(TaskManagerState, List(TaskManagerEvent)) {
  remove_client_with_lost(state, self_id, True)
}

pub fn replace_placeholder(
  state: TaskManagerState,
  placeholder: Int,
  real_id: Int,
) -> TaskManagerState {
  let queues =
    sorted_queues(state)
    |> list.fold(state.queues, fn(acc, entry) {
      let #(task_id, queue) = entry
      let real_exists = list.contains(queue, real_id)
      let queue =
        queue
        |> list.filter(fn(client_id) { client_id != placeholder })
      let queue = case real_exists {
        True -> queue
        False -> replace_once(queue_for(state, task_id), placeholder, real_id)
      }
      set_queue(acc, task_id, queue)
    })
  TaskManagerState(..state, queues: queues)
}

pub fn scrub_not_in_quorum(
  state: TaskManagerState,
  quorum: List(Int),
) -> #(TaskManagerState, List(TaskManagerEvent)) {
  let #(queues, events) =
    sorted_queues(state)
    |> list.fold(#(state.queues, []), fn(acc, entry) {
      let #(queues, events) = acc
      let #(task_id, queue) = entry
      let old = head(queue)
      let scrubbed =
        queue
        |> list.filter(fn(client_id) { list.contains(quorum, client_id) })
      let new = head(scrubbed)
      let queues = set_queue(queues, task_id, scrubbed)
      let events = append_queue_changed(events, task_id, old, new)
      #(queues, events)
    })
  #(TaskManagerState(..state, queues: queues), events)
}

pub fn resubmit(
  state: TaskManagerState,
  op: TaskManagerOp,
  message_id: Int,
  next_message_id: Int,
) -> Result(
  #(TaskManagerState, Option(TaskManagerOp), Option(PendingOp)),
  TaskManagerError,
) {
  let task_id = op_task_id(op)
  case remove_pending(state, task_id, op_pending_kind(op), message_id) {
    Error(detail) -> Error(UnexpectedResubmit(op, detail))
    Ok(state) ->
      case op {
        Volunteer(_) -> {
          case latest_pending(state, task_id) {
            Some(PendingOp(PendingAbandon, _)) -> Ok(#(state, None, None))
            _ -> {
              let pending = PendingOp(PendingVolunteer, next_message_id)
              let state = add_pending(state, task_id, pending)
              Ok(#(state, Some(Volunteer(task_id)), Some(pending)))
            }
          }
        }
        Abandon(_) -> Ok(#(state, None, None))
        Complete(_) -> Ok(#(state, None, None))
      }
  }
}

pub fn rollback(
  state: TaskManagerState,
  op: TaskManagerOp,
  message_id: Int,
) -> Result(#(TaskManagerState, List(TaskManagerEvent)), TaskManagerError) {
  let task_id = op_task_id(op)
  case pop_latest_pending(state, task_id, op_pending_kind(op), message_id) {
    Error(detail) -> Error(UnexpectedRollback(op, detail))
    Ok(state) -> Ok(#(state, [RolledBack(task_id)]))
  }
}

pub fn apply_stashed_op(
  state: TaskManagerState,
  _op: TaskManagerOp,
) -> #(TaskManagerState, Option(TaskManagerOp)) {
  #(state, None)
}

fn apply_volunteer_core(
  state: TaskManagerState,
  task_id: String,
  author: Int,
  quorum: List(Int),
  local: Bool,
) -> #(TaskManagerState, List(TaskManagerEvent)) {
  case list.contains(quorum, author) {
    False -> #(state, [])
    True -> {
      let queue = queue_for(state, task_id)
      case list.contains(queue, author) {
        True -> #(state, [])
        False -> {
          let old = head(queue)
          let queue = list.append(queue, [author])
          let new = head(queue)
          let state =
            TaskManagerState(
              ..state,
              queues: set_queue(state.queues, task_id, queue),
            )
          let events = append_queue_changed([], task_id, old, new)
          let events = case local && new == Some(author) {
            True -> list.append(events, [Assigned(task_id)])
            False -> events
          }
          #(state, events)
        }
      }
    }
  }
}

fn apply_abandon_core(
  state: TaskManagerState,
  task_id: String,
  author: Int,
  local: Bool,
) -> #(TaskManagerState, List(TaskManagerEvent)) {
  let queue = queue_for(state, task_id)
  let old = head(queue)
  let queue = remove_client_from_queue(queue, author)
  let new = head(queue)
  let state =
    TaskManagerState(..state, queues: set_queue(state.queues, task_id, queue))
  let events = append_queue_changed([], task_id, old, new)
  let events = case local {
    True -> list.append(events, [Abandoned(task_id)])
    False -> events
  }
  #(state, events)
}

fn apply_complete_core(
  state: TaskManagerState,
  task_id: String,
) -> #(TaskManagerState, List(TaskManagerEvent)) {
  let queue = queue_for(state, task_id)
  let old = head(queue)
  let state =
    TaskManagerState(..state, queues: dict.delete(state.queues, task_id))
  let events = append_queue_changed([], task_id, old, None)
  #(state, list.append(events, [Completed(task_id)]))
}

fn remove_client_with_lost(
  state: TaskManagerState,
  client_id: Int,
  emit_lost: Bool,
) -> #(TaskManagerState, List(TaskManagerEvent)) {
  let #(queues, events) =
    sorted_queues(state)
    |> list.fold(#(state.queues, []), fn(acc, entry) {
      let #(queues, events) = acc
      let #(task_id, queue) = entry
      let old = head(queue)
      let queue = remove_client_from_queue(queue, client_id)
      let new = head(queue)
      let queues = set_queue(queues, task_id, queue)
      let events = case emit_lost && old == Some(client_id) {
        True -> list.append(events, [Lost(task_id)])
        False -> events
      }
      let events = append_queue_changed(events, task_id, old, new)
      #(queues, events)
    })
  #(TaskManagerState(..state, queues: queues), events)
}

fn add_pending(
  state: TaskManagerState,
  task_id: String,
  op: PendingOp,
) -> TaskManagerState {
  let pending = case dict.get(state.pending, task_id) {
    Ok(ops) -> list.append(ops, [op])
    Error(_) -> [op]
  }
  TaskManagerState(
    ..state,
    pending: dict.insert(state.pending, task_id, pending),
  )
}

fn pop_oldest_pending(
  state: TaskManagerState,
  task_id: String,
  kind: PendingKind,
  message_id: Int,
) -> Result(TaskManagerState, String) {
  case dict.get(state.pending, task_id) {
    Error(_) -> Error("no pending op for task \"" <> task_id <> "\"")
    Ok([]) -> Error("no pending op for task \"" <> task_id <> "\"")
    Ok([PendingOp(found_kind, found_id), ..rest]) -> {
      case found_kind == kind && found_id == message_id {
        True -> Ok(set_pending(state, task_id, rest))
        False -> Error("oldest pending op did not match")
      }
    }
  }
}

fn pop_latest_pending(
  state: TaskManagerState,
  task_id: String,
  kind: PendingKind,
  message_id: Int,
) -> Result(TaskManagerState, String) {
  case dict.get(state.pending, task_id) {
    Error(_) -> Error("no pending op for task \"" <> task_id <> "\"")
    Ok([]) -> Error("no pending op for task \"" <> task_id <> "\"")
    Ok(ops) -> {
      let reversed = list.reverse(ops)
      case reversed {
        [PendingOp(found_kind, found_id), ..rest] -> {
          case found_kind == kind && found_id == message_id {
            True -> Ok(set_pending(state, task_id, list.reverse(rest)))
            False -> Error("latest pending op did not match")
          }
        }
        [] -> Error("no pending op for task \"" <> task_id <> "\"")
      }
    }
  }
}

fn remove_pending(
  state: TaskManagerState,
  task_id: String,
  kind: PendingKind,
  message_id: Int,
) -> Result(TaskManagerState, String) {
  case dict.get(state.pending, task_id) {
    Error(_) -> Error("no pending op for task \"" <> task_id <> "\"")
    Ok(ops) -> {
      case remove_first_matching_pending(ops, kind, message_id, []) {
        Error(_) -> Error("matching pending op not found")
        Ok(remaining) -> Ok(set_pending(state, task_id, remaining))
      }
    }
  }
}

fn remove_first_matching_pending(
  ops: List(PendingOp),
  kind: PendingKind,
  message_id: Int,
  seen: List(PendingOp),
) -> Result(List(PendingOp), Nil) {
  case ops {
    [] -> Error(Nil)
    [PendingOp(found_kind, found_id) as op, ..rest] -> {
      case found_kind == kind && found_id == message_id {
        True -> Ok(list.append(list.reverse(seen), rest))
        False ->
          remove_first_matching_pending(rest, kind, message_id, [op, ..seen])
      }
    }
  }
}

fn set_pending(
  state: TaskManagerState,
  task_id: String,
  ops: List(PendingOp),
) -> TaskManagerState {
  let pending = case ops {
    [] -> dict.delete(state.pending, task_id)
    _ -> dict.insert(state.pending, task_id, ops)
  }
  TaskManagerState(..state, pending: pending)
}

fn latest_pending(
  state: TaskManagerState,
  task_id: String,
) -> Option(PendingOp) {
  case dict.get(state.pending, task_id) {
    Ok(ops) ->
      case list.reverse(ops) {
        [op, ..] -> Some(op)
        [] -> None
      }
    Error(_) -> None
  }
}

fn op_task_id(op: TaskManagerOp) -> String {
  case op {
    Volunteer(task_id) -> task_id
    Abandon(task_id) -> task_id
    Complete(task_id) -> task_id
  }
}

fn op_pending_kind(op: TaskManagerOp) -> PendingKind {
  case op {
    Volunteer(_) -> PendingVolunteer
    Abandon(_) -> PendingAbandon
    Complete(_) -> PendingComplete
  }
}

fn queue_for(state: TaskManagerState, task_id: String) -> List(Int) {
  case dict.get(state.queues, task_id) {
    Ok(queue) -> queue
    Error(_) -> []
  }
}

fn assignee(state: TaskManagerState, task_id: String) -> Option(Int) {
  queue_for(state, task_id) |> head
}

fn head(queue: List(Int)) -> Option(Int) {
  case queue {
    [client_id, ..] -> Some(client_id)
    [] -> None
  }
}

fn set_queue(
  queues: Dict(String, List(Int)),
  task_id: String,
  queue: List(Int),
) -> Dict(String, List(Int)) {
  case queue {
    [] -> dict.delete(queues, task_id)
    _ -> dict.insert(queues, task_id, queue)
  }
}

fn sorted_queues(state: TaskManagerState) -> List(#(String, List(Int))) {
  dict.to_list(state.queues)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

fn append_queue_changed(
  events: List(TaskManagerEvent),
  task_id: String,
  old: Option(Int),
  new: Option(Int),
) -> List(TaskManagerEvent) {
  case old == new {
    True -> events
    False -> list.append(events, [QueueChanged(task_id, old, new)])
  }
}

fn remove_client_from_queue(queue: List(Int), client_id: Int) -> List(Int) {
  queue
  |> list.filter(fn(queued_id) { queued_id != client_id })
}

fn replace_once(queue: List(Int), placeholder: Int, real_id: Int) -> List(Int) {
  case queue {
    [] -> []
    [client_id, ..rest] -> {
      case client_id == placeholder {
        True -> [real_id, ..rest]
        False -> [client_id, ..replace_once(rest, placeholder, real_id)]
      }
    }
  }
}
