/// <reference types="./task_manager_kernel.d.mts" />
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";

export class TaskManagerState extends $CustomType {
  constructor(queues, pending) {
    super();
    this.queues = queues;
    this.pending = pending;
  }
}
export const TaskManagerState$TaskManagerState = (queues, pending) =>
  new TaskManagerState(queues, pending);
export const TaskManagerState$isTaskManagerState = (value) =>
  value instanceof TaskManagerState;
export const TaskManagerState$TaskManagerState$queues = (value) => value.queues;
export const TaskManagerState$TaskManagerState$0 = (value) => value.queues;
export const TaskManagerState$TaskManagerState$pending = (value) =>
  value.pending;
export const TaskManagerState$TaskManagerState$1 = (value) => value.pending;

export class Volunteer extends $CustomType {
  constructor(task_id) {
    super();
    this.task_id = task_id;
  }
}
export const TaskManagerOperation$Volunteer = (task_id) =>
  new Volunteer(task_id);
export const TaskManagerOperation$isVolunteer = (value) =>
  value instanceof Volunteer;
export const TaskManagerOperation$Volunteer$task_id = (value) => value.task_id;
export const TaskManagerOperation$Volunteer$0 = (value) => value.task_id;

export class Abandon extends $CustomType {
  constructor(task_id) {
    super();
    this.task_id = task_id;
  }
}
export const TaskManagerOperation$Abandon = (task_id) => new Abandon(task_id);
export const TaskManagerOperation$isAbandon = (value) =>
  value instanceof Abandon;
export const TaskManagerOperation$Abandon$task_id = (value) => value.task_id;
export const TaskManagerOperation$Abandon$0 = (value) => value.task_id;

export class Complete extends $CustomType {
  constructor(task_id) {
    super();
    this.task_id = task_id;
  }
}
export const TaskManagerOperation$Complete = (task_id) => new Complete(task_id);
export const TaskManagerOperation$isComplete = (value) =>
  value instanceof Complete;
export const TaskManagerOperation$Complete$task_id = (value) => value.task_id;
export const TaskManagerOperation$Complete$0 = (value) => value.task_id;

export const TaskManagerOperation$task_id = (value) => value.task_id;

export class PendingOperation extends $CustomType {
  constructor(kind, message_id) {
    super();
    this.kind = kind;
    this.message_id = message_id;
  }
}
export const PendingOperation$PendingOperation = (kind, message_id) =>
  new PendingOperation(kind, message_id);
export const PendingOperation$isPendingOperation = (value) =>
  value instanceof PendingOperation;
export const PendingOperation$PendingOperation$kind = (value) => value.kind;
export const PendingOperation$PendingOperation$0 = (value) => value.kind;
export const PendingOperation$PendingOperation$message_id = (value) =>
  value.message_id;
export const PendingOperation$PendingOperation$1 = (value) => value.message_id;

export class PendingVolunteer extends $CustomType {}
export const PendingKind$PendingVolunteer$const = new PendingVolunteer();
export const PendingKind$PendingVolunteer = () =>
  PendingKind$PendingVolunteer$const;
export const PendingKind$isPendingVolunteer = (value) =>
  value instanceof PendingVolunteer;

export class PendingAbandon extends $CustomType {}
export const PendingKind$PendingAbandon$const = new PendingAbandon();
export const PendingKind$PendingAbandon = () =>
  PendingKind$PendingAbandon$const;
export const PendingKind$isPendingAbandon = (value) =>
  value instanceof PendingAbandon;

export class PendingComplete extends $CustomType {}
export const PendingKind$PendingComplete$const = new PendingComplete();
export const PendingKind$PendingComplete = () =>
  PendingKind$PendingComplete$const;
export const PendingKind$isPendingComplete = (value) =>
  value instanceof PendingComplete;

export class QueueChanged extends $CustomType {
  constructor(task_id, old_assignee, new_assignee) {
    super();
    this.task_id = task_id;
    this.old_assignee = old_assignee;
    this.new_assignee = new_assignee;
  }
}
export const TaskManagerEvent$QueueChanged = (task_id, old_assignee, new_assignee) =>
  new QueueChanged(task_id, old_assignee, new_assignee);
export const TaskManagerEvent$isQueueChanged = (value) =>
  value instanceof QueueChanged;
export const TaskManagerEvent$QueueChanged$task_id = (value) => value.task_id;
export const TaskManagerEvent$QueueChanged$0 = (value) => value.task_id;
export const TaskManagerEvent$QueueChanged$old_assignee = (value) =>
  value.old_assignee;
export const TaskManagerEvent$QueueChanged$1 = (value) => value.old_assignee;
export const TaskManagerEvent$QueueChanged$new_assignee = (value) =>
  value.new_assignee;
export const TaskManagerEvent$QueueChanged$2 = (value) => value.new_assignee;

export class Assigned extends $CustomType {
  constructor(task_id) {
    super();
    this.task_id = task_id;
  }
}
export const TaskManagerEvent$Assigned = (task_id) => new Assigned(task_id);
export const TaskManagerEvent$isAssigned = (value) => value instanceof Assigned;
export const TaskManagerEvent$Assigned$task_id = (value) => value.task_id;
export const TaskManagerEvent$Assigned$0 = (value) => value.task_id;

export class Lost extends $CustomType {
  constructor(task_id) {
    super();
    this.task_id = task_id;
  }
}
export const TaskManagerEvent$Lost = (task_id) => new Lost(task_id);
export const TaskManagerEvent$isLost = (value) => value instanceof Lost;
export const TaskManagerEvent$Lost$task_id = (value) => value.task_id;
export const TaskManagerEvent$Lost$0 = (value) => value.task_id;

export class Completed extends $CustomType {
  constructor(task_id) {
    super();
    this.task_id = task_id;
  }
}
export const TaskManagerEvent$Completed = (task_id) => new Completed(task_id);
export const TaskManagerEvent$isCompleted = (value) =>
  value instanceof Completed;
export const TaskManagerEvent$Completed$task_id = (value) => value.task_id;
export const TaskManagerEvent$Completed$0 = (value) => value.task_id;

export class Abandoned extends $CustomType {
  constructor(task_id) {
    super();
    this.task_id = task_id;
  }
}
export const TaskManagerEvent$Abandoned = (task_id) => new Abandoned(task_id);
export const TaskManagerEvent$isAbandoned = (value) =>
  value instanceof Abandoned;
export const TaskManagerEvent$Abandoned$task_id = (value) => value.task_id;
export const TaskManagerEvent$Abandoned$0 = (value) => value.task_id;

export class RolledBack extends $CustomType {
  constructor(task_id) {
    super();
    this.task_id = task_id;
  }
}
export const TaskManagerEvent$RolledBack = (task_id) => new RolledBack(task_id);
export const TaskManagerEvent$isRolledBack = (value) =>
  value instanceof RolledBack;
export const TaskManagerEvent$RolledBack$task_id = (value) => value.task_id;
export const TaskManagerEvent$RolledBack$0 = (value) => value.task_id;

export const TaskManagerEvent$task_id = (value) => value.task_id;

export class AssignedNow extends $CustomType {}
export const VolunteerOutcome$AssignedNow$const = new AssignedNow();
export const VolunteerOutcome$AssignedNow = () =>
  VolunteerOutcome$AssignedNow$const;
export const VolunteerOutcome$isAssignedNow = (value) =>
  value instanceof AssignedNow;

export class Waiting extends $CustomType {}
export const VolunteerOutcome$Waiting$const = new Waiting();
export const VolunteerOutcome$Waiting = () => VolunteerOutcome$Waiting$const;
export const VolunteerOutcome$isWaiting = (value) => value instanceof Waiting;

export class CompletedBeforeAssignment extends $CustomType {}
export const VolunteerOutcome$CompletedBeforeAssignment$const =
  new CompletedBeforeAssignment();
export const VolunteerOutcome$CompletedBeforeAssignment = () =>
  VolunteerOutcome$CompletedBeforeAssignment$const;
export const VolunteerOutcome$isCompletedBeforeAssignment = (value) =>
  value instanceof CompletedBeforeAssignment;

export class AbandonedBeforeAssignment extends $CustomType {}
export const VolunteerOutcome$AbandonedBeforeAssignment$const =
  new AbandonedBeforeAssignment();
export const VolunteerOutcome$AbandonedBeforeAssignment = () =>
  VolunteerOutcome$AbandonedBeforeAssignment$const;
export const VolunteerOutcome$isAbandonedBeforeAssignment = (value) =>
  value instanceof AbandonedBeforeAssignment;

export class DisconnectedBeforeAssignment extends $CustomType {}
export const VolunteerOutcome$DisconnectedBeforeAssignment$const =
  new DisconnectedBeforeAssignment();
export const VolunteerOutcome$DisconnectedBeforeAssignment = () =>
  VolunteerOutcome$DisconnectedBeforeAssignment$const;
export const VolunteerOutcome$isDisconnectedBeforeAssignment = (value) =>
  value instanceof DisconnectedBeforeAssignment;

export class RolledBackBeforeAssignment extends $CustomType {}
export const VolunteerOutcome$RolledBackBeforeAssignment$const =
  new RolledBackBeforeAssignment();
export const VolunteerOutcome$RolledBackBeforeAssignment = () =>
  VolunteerOutcome$RolledBackBeforeAssignment$const;
export const VolunteerOutcome$isRolledBackBeforeAssignment = (value) =>
  value instanceof RolledBackBeforeAssignment;

export class NotAssigned extends $CustomType {
  constructor(task_id) {
    super();
    this.task_id = task_id;
  }
}
export const TaskManagerError$NotAssigned = (task_id) =>
  new NotAssigned(task_id);
export const TaskManagerError$isNotAssigned = (value) =>
  value instanceof NotAssigned;
export const TaskManagerError$NotAssigned$task_id = (value) => value.task_id;
export const TaskManagerError$NotAssigned$0 = (value) => value.task_id;

export class UnexpectedAck extends $CustomType {
  constructor(operation, detail) {
    super();
    this.operation = operation;
    this.detail = detail;
  }
}
export const TaskManagerError$UnexpectedAck = (operation, detail) =>
  new UnexpectedAck(operation, detail);
export const TaskManagerError$isUnexpectedAck = (value) =>
  value instanceof UnexpectedAck;
export const TaskManagerError$UnexpectedAck$operation = (value) =>
  value.operation;
export const TaskManagerError$UnexpectedAck$0 = (value) => value.operation;
export const TaskManagerError$UnexpectedAck$detail = (value) => value.detail;
export const TaskManagerError$UnexpectedAck$1 = (value) => value.detail;

export class UnexpectedRollback extends $CustomType {
  constructor(operation, detail) {
    super();
    this.operation = operation;
    this.detail = detail;
  }
}
export const TaskManagerError$UnexpectedRollback = (operation, detail) =>
  new UnexpectedRollback(operation, detail);
export const TaskManagerError$isUnexpectedRollback = (value) =>
  value instanceof UnexpectedRollback;
export const TaskManagerError$UnexpectedRollback$operation = (value) =>
  value.operation;
export const TaskManagerError$UnexpectedRollback$0 = (value) => value.operation;
export const TaskManagerError$UnexpectedRollback$detail = (value) =>
  value.detail;
export const TaskManagerError$UnexpectedRollback$1 = (value) => value.detail;

export class UnexpectedResubmit extends $CustomType {
  constructor(operation, detail) {
    super();
    this.operation = operation;
    this.detail = detail;
  }
}
export const TaskManagerError$UnexpectedResubmit = (operation, detail) =>
  new UnexpectedResubmit(operation, detail);
export const TaskManagerError$isUnexpectedResubmit = (value) =>
  value instanceof UnexpectedResubmit;
export const TaskManagerError$UnexpectedResubmit$operation = (value) =>
  value.operation;
export const TaskManagerError$UnexpectedResubmit$0 = (value) => value.operation;
export const TaskManagerError$UnexpectedResubmit$detail = (value) =>
  value.detail;
export const TaskManagerError$UnexpectedResubmit$1 = (value) => value.detail;

export function new$() {
  return new TaskManagerState($dict.new$(), $dict.new$());
}

function set_queue(queues, task_id, queue) {
  if (queue instanceof $Empty) {
    return $dict.delete$(queues, task_id);
  } else {
    return $dict.insert(queues, task_id, queue);
  }
}

export function from_summary(queues) {
  let _block;
  let _pipe = queues;
  _block = $list.fold(
    _pipe,
    $dict.new$(),
    (acc, entry) => {
      let task_id = entry[0];
      let queue = entry[1];
      return set_queue(acc, task_id, queue);
    },
  );
  let queues$1 = _block;
  return new TaskManagerState(queues$1, $dict.new$());
}

function sorted_queues(state) {
  let _pipe = $dict.to_list(state.queues);
  return $list.sort(_pipe, (a, b) => { return $string.compare(a[0], b[0]); });
}

export function summary_queues(state) {
  let _pipe = sorted_queues(state);
  return $list.filter(
    _pipe,
    (entry) => {
      let queue = entry[1];
      return !(queue instanceof $Empty);
    },
  );
}

function queue_for(state, task_id) {
  let $ = $dict.get(state.queues, task_id);
  if ($ instanceof Ok) {
    let queue = $[0];
    return queue;
  } else {
    return $List$Empty$const;
  }
}

/**
 * The client that holds the task now, which is the client at the front of
 * the queue. The result is `Error(Nil)` for an empty queue.
 * 
 * @ignore
 */
function assignee(state, task_id) {
  let _pipe = queue_for(state, task_id);
  return $list.first(_pipe);
}

export function assigned(state, task_id, self_id, connected) {
  if (connected) {
    return isEqual(assignee(state, task_id), new Ok(self_id));
  } else {
    return connected;
  }
}

export function queued(state, task_id, self_id, connected) {
  if (connected) {
    return $list.contains(queue_for(state, task_id), self_id);
  } else {
    return connected;
  }
}

function latest_pending(state, task_id) {
  let $ = $dict.get(state.pending, task_id);
  if ($ instanceof Ok) {
    let operations = $[0];
    let $1 = $list.reverse(operations);
    if ($1 instanceof $Empty) {
      return new Error(undefined);
    } else {
      let operation = $1.head;
      return new Ok(operation);
    }
  } else {
    return $;
  }
}

export function queued_optimistically(state, task_id, self_id) {
  let $ = latest_pending(state, task_id);
  if ($ instanceof Ok) {
    let $1 = $[0].kind;
    if ($1 instanceof PendingVolunteer) {
      return true;
    } else if ($1 instanceof PendingAbandon) {
      return false;
    } else {
      return false;
    }
  } else {
    return $list.contains(queue_for(state, task_id), self_id);
  }
}

function add_pending(state, task_id, operation) {
  let _block;
  let $ = $dict.get(state.pending, task_id);
  if ($ instanceof Ok) {
    let operations = $[0];
    _block = $list.append(operations, toList([operation]));
  } else {
    _block = toList([operation]);
  }
  let pending = _block;
  return new TaskManagerState(
    state.queues,
    $dict.insert(state.pending, task_id, pending),
  );
}

export function volunteer(state, task_id, self_id, message_id) {
  let $ = queued_optimistically(state, task_id, self_id);
  if ($) {
    let _block;
    let $1 = assigned(state, task_id, self_id, true);
    if ($1) {
      _block = VolunteerOutcome$AssignedNow$const;
    } else {
      _block = VolunteerOutcome$Waiting$const;
    }
    let outcome = _block;
    return [state, Option$None$const, outcome];
  } else {
    let state$1 = add_pending(
      state,
      task_id,
      new PendingOperation(PendingKind$PendingVolunteer$const, message_id),
    );
    return [
      state$1,
      new Some(new Volunteer(task_id)),
      VolunteerOutcome$Waiting$const,
    ];
  }
}

function append_queue_changed(events, task_id, old, new$) {
  let $ = isEqual(old, new$);
  if ($) {
    return events;
  } else {
    return $list.append(events, toList([new QueueChanged(task_id, old, new$)]));
  }
}

/**
 * This function drops a volunteer from a client that is not in the room at
 * this sequence point.
 *
 * The invariant is that a queue names only the clients that the roster names.
 * That invariant makes the leave-driven release complete. `remove_client` on a
 * sequenced `"leave"` is the only operation that frees a lock whose holder
 * left the room. A client that entered a queue without membership could thus
 * hold a role that nothing releases.
 *
 * Every replica must give the same result here, or the queues diverge. Thus
 * this function takes `meta.roster`, which the kernel rebuilds at the sequence
 * point of the operation. It does not take `meta.quorum`, whose defensive
 * additions differ between a replica that applies the operation live and a
 * replica that replays it.
 * 
 * @ignore
 */
function apply_volunteer_core(state, task_id, author, roster, local) {
  let $ = $list.contains(roster, author);
  if ($) {
    let queue = queue_for(state, task_id);
    let $1 = $list.contains(queue, author);
    if ($1) {
      return [state, $List$Empty$const];
    } else {
      let old = $option.from_result($list.first(queue));
      let queue$1 = $list.append(queue, toList([author]));
      let new$1 = $option.from_result($list.first(queue$1));
      let state$1 = new TaskManagerState(
        set_queue(state.queues, task_id, queue$1),
        state.pending,
      );
      let events = append_queue_changed($List$Empty$const, task_id, old, new$1);
      let _block;
      let $2 = local && (isEqual(new$1, new Some(author)));
      if ($2) {
        _block = $list.append(events, toList([new Assigned(task_id)]));
      } else {
        _block = events;
      }
      let events$1 = _block;
      return [state$1, events$1];
    }
  } else {
    return [state, $List$Empty$const];
  }
}

export function volunteer_detached(state, task_id, self_id) {
  let $ = apply_volunteer_core(state, task_id, self_id, toList([self_id]), true);
  let state$1 = $[0];
  let events = $[1];
  let _block;
  let $1 = assigned(state$1, task_id, self_id, true);
  if ($1) {
    _block = VolunteerOutcome$AssignedNow$const;
  } else {
    _block = VolunteerOutcome$Waiting$const;
  }
  let outcome = _block;
  return [state$1, events, outcome];
}

export function abandon(state, task_id, self_id, message_id) {
  let $ = queued_optimistically(state, task_id, self_id);
  if ($) {
    let state$1 = add_pending(
      state,
      task_id,
      new PendingOperation(PendingKind$PendingAbandon$const, message_id),
    );
    return [
      state$1,
      new Some(new Abandon(task_id)),
      toList([new Abandoned(task_id)]),
    ];
  } else {
    return [state, Option$None$const, $List$Empty$const];
  }
}

function remove_client_from_queue(queue, client_id) {
  let _pipe = queue;
  return $list.filter(_pipe, (queued_id) => { return queued_id !== client_id; });
}

function apply_abandon_core(state, task_id, author, local) {
  let queue = queue_for(state, task_id);
  let old = $option.from_result($list.first(queue));
  let queue$1 = remove_client_from_queue(queue, author);
  let new$1 = $option.from_result($list.first(queue$1));
  let state$1 = new TaskManagerState(
    set_queue(state.queues, task_id, queue$1),
    state.pending,
  );
  let events = append_queue_changed($List$Empty$const, task_id, old, new$1);
  let _block;
  if (local) {
    _block = $list.append(events, toList([new Abandoned(task_id)]));
  } else {
    _block = events;
  }
  let events$1 = _block;
  return [state$1, events$1];
}

export function abandon_detached(state, task_id, self_id) {
  return apply_abandon_core(state, task_id, self_id, true);
}

export function complete(state, task_id, self_id, message_id) {
  let $ = assigned(state, task_id, self_id, true);
  if ($) {
    let state$1 = add_pending(
      state,
      task_id,
      new PendingOperation(PendingKind$PendingComplete$const, message_id),
    );
    return new Ok([state$1, new Complete(task_id)]);
  } else {
    return new Error(new NotAssigned(task_id));
  }
}

function apply_complete_core(state, task_id) {
  let queue = queue_for(state, task_id);
  let old = $option.from_result($list.first(queue));
  let state$1 = new TaskManagerState(
    $dict.delete$(state.queues, task_id),
    state.pending,
  );
  let events = append_queue_changed(
    $List$Empty$const,
    task_id,
    old,
    Option$None$const,
  );
  return [state$1, $list.append(events, toList([new Completed(task_id)]))];
}

export function complete_detached(state, task_id) {
  return apply_complete_core(state, task_id);
}

export function apply_remote(state, operation, author, roster) {
  if (operation instanceof Volunteer) {
    let task_id = operation.task_id;
    return apply_volunteer_core(state, task_id, author, roster, false);
  } else if (operation instanceof Abandon) {
    let task_id = operation.task_id;
    return apply_abandon_core(state, task_id, author, false);
  } else {
    let task_id = operation.task_id;
    return apply_complete_core(state, task_id);
  }
}

function set_pending(state, task_id, operations) {
  let _block;
  if (operations instanceof $Empty) {
    _block = $dict.delete$(state.pending, task_id);
  } else {
    _block = $dict.insert(state.pending, task_id, operations);
  }
  let pending = _block;
  return new TaskManagerState(state.queues, pending);
}

function pop_oldest_pending(state, task_id, kind, message_id) {
  let $ = $dict.get(state.pending, task_id);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $Empty) {
      return new Error(("no pending op for task \"" + task_id) + "\"");
    } else {
      let rest = $1.tail;
      let found_kind = $1.head.kind;
      let found_id = $1.head.message_id;
      let $2 = (isEqual(found_kind, kind)) && (found_id === message_id);
      if ($2) {
        return new Ok(set_pending(state, task_id, rest));
      } else {
        return new Error("oldest pending op did not match");
      }
    }
  } else {
    return new Error(("no pending op for task \"" + task_id) + "\"");
  }
}

function operation_pending_kind(operation) {
  if (operation instanceof Volunteer) {
    return PendingKind$PendingVolunteer$const;
  } else if (operation instanceof Abandon) {
    return PendingKind$PendingAbandon$const;
  } else {
    return PendingKind$PendingComplete$const;
  }
}

function operation_task_id(operation) {
  if (operation instanceof Volunteer) {
    let task_id = operation.task_id;
    return task_id;
  } else if (operation instanceof Abandon) {
    let task_id = operation.task_id;
    return task_id;
  } else {
    let task_id = operation.task_id;
    return task_id;
  }
}

export function ack_local(state, operation, author, message_id, roster) {
  let task_id = operation_task_id(operation);
  let expected = operation_pending_kind(operation);
  let $ = pop_oldest_pending(state, task_id, expected, message_id);
  if ($ instanceof Ok) {
    let state$1 = $[0];
    let _block;
    if (operation instanceof Volunteer) {
      _block = apply_volunteer_core(state$1, task_id, author, roster, true);
    } else if (operation instanceof Abandon) {
      _block = apply_abandon_core(state$1, task_id, author, true);
    } else {
      _block = apply_complete_core(state$1, task_id);
    }
    let $1 = _block;
    let state$2 = $1[0];
    let events = $1[1];
    return new Ok([state$2, events]);
  } else {
    let detail = $[0];
    return new Error(new UnexpectedAck(operation, detail));
  }
}

function remove_client_with_lost(state, client_id, emit_lost) {
  let _block;
  let _pipe = sorted_queues(state);
  _block = $list.fold(
    _pipe,
    [state.queues, $List$Empty$const],
    (acc, entry) => {
      let queues = acc[0];
      let events = acc[1];
      let task_id = entry[0];
      let queue = entry[1];
      let old = $option.from_result($list.first(queue));
      let queue$1 = remove_client_from_queue(queue, client_id);
      let new$1 = $option.from_result($list.first(queue$1));
      let queues$1 = set_queue(queues, task_id, queue$1);
      let _block$1;
      let $1 = emit_lost && (isEqual(old, new Some(client_id)));
      if ($1) {
        _block$1 = $list.append(events, toList([new Lost(task_id)]));
      } else {
        _block$1 = events;
      }
      let events$1 = _block$1;
      let events$2 = append_queue_changed(events$1, task_id, old, new$1);
      return [queues$1, events$2];
    },
  );
  let $ = _block;
  let queues = $[0];
  let events = $[1];
  return [new TaskManagerState(queues, state.pending), events];
}

export function remove_client(state, client_id) {
  return remove_client_with_lost(state, client_id, false);
}

export function on_disconnect(state, self_id) {
  return remove_client_with_lost(state, self_id, true);
}

function replace_once(queue, placeholder, real_id) {
  if (queue instanceof $Empty) {
    return queue;
  } else {
    let client_id = queue.head;
    let rest = queue.tail;
    let $ = client_id === placeholder;
    if ($) {
      return listPrepend(real_id, rest);
    } else {
      return listPrepend(client_id, replace_once(rest, placeholder, real_id));
    }
  }
}

export function replace_placeholder(state, placeholder, real_id) {
  let _block;
  let _pipe = sorted_queues(state);
  _block = $list.fold(
    _pipe,
    state.queues,
    (acc, entry) => {
      let task_id = entry[0];
      let queue = entry[1];
      let real_exists = $list.contains(queue, real_id);
      let _block$1;
      let _pipe$1 = queue;
      _block$1 = $list.filter(
        _pipe$1,
        (client_id) => { return client_id !== placeholder; },
      );
      let queue$1 = _block$1;
      let _block$2;
      if (real_exists) {
        _block$2 = queue$1;
      } else {
        _block$2 = replace_once(queue_for(state, task_id), placeholder, real_id);
      }
      let queue$2 = _block$2;
      return set_queue(acc, task_id, queue$2);
    },
  );
  let queues = _block;
  return new TaskManagerState(queues, state.pending);
}

export function scrub_not_in_roster(state, roster) {
  let _block;
  let _pipe = sorted_queues(state);
  _block = $list.fold(
    _pipe,
    [state.queues, $List$Empty$const],
    (acc, entry) => {
      let queues = acc[0];
      let events = acc[1];
      let task_id = entry[0];
      let queue = entry[1];
      let old = $option.from_result($list.first(queue));
      let _block$1;
      let _pipe$1 = queue;
      _block$1 = $list.filter(
        _pipe$1,
        (client_id) => { return $list.contains(roster, client_id); },
      );
      let scrubbed = _block$1;
      let new$1 = $option.from_result($list.first(scrubbed));
      let queues$1 = set_queue(queues, task_id, scrubbed);
      let events$1 = append_queue_changed(events, task_id, old, new$1);
      return [queues$1, events$1];
    },
  );
  let $ = _block;
  let queues = $[0];
  let events = $[1];
  return [new TaskManagerState(queues, state.pending), events];
}

function remove_first_matching_pending(
  loop$operations,
  loop$kind,
  loop$message_id,
  loop$seen
) {
  while (true) {
    let operations = loop$operations;
    let kind = loop$kind;
    let message_id = loop$message_id;
    let seen = loop$seen;
    if (operations instanceof $Empty) {
      return new Error(undefined);
    } else {
      let operation = operations.head;
      let rest = operations.tail;
      let found_kind = operations.head.kind;
      let found_id = operations.head.message_id;
      let $ = (isEqual(found_kind, kind)) && (found_id === message_id);
      if ($) {
        return new Ok($list.append($list.reverse(seen), rest));
      } else {
        loop$operations = rest;
        loop$kind = kind;
        loop$message_id = message_id;
        loop$seen = listPrepend(operation, seen);
      }
    }
  }
}

function remove_pending(state, task_id, kind, message_id) {
  let $ = $dict.get(state.pending, task_id);
  if ($ instanceof Ok) {
    let operations = $[0];
    let $1 = remove_first_matching_pending(
      operations,
      kind,
      message_id,
      $List$Empty$const,
    );
    if ($1 instanceof Ok) {
      let remaining = $1[0];
      return new Ok(set_pending(state, task_id, remaining));
    } else {
      return new Error("matching pending op not found");
    }
  } else {
    return new Error(("no pending op for task \"" + task_id) + "\"");
  }
}

export function resubmit(state, operation, message_id, next_message_id) {
  let task_id = operation_task_id(operation);
  let $ = remove_pending(
    state,
    task_id,
    operation_pending_kind(operation),
    message_id,
  );
  if ($ instanceof Ok) {
    let state$1 = $[0];
    if (operation instanceof Volunteer) {
      let $1 = latest_pending(state$1, task_id);
      if ($1 instanceof Ok) {
        let $2 = $1[0].kind;
        if ($2 instanceof PendingVolunteer) {
          let pending = new PendingOperation(
            PendingKind$PendingVolunteer$const,
            next_message_id,
          );
          let state$2 = add_pending(state$1, task_id, pending);
          return new Ok(
            [state$2, new Some(new Volunteer(task_id)), new Some(pending)],
          );
        } else if ($2 instanceof PendingAbandon) {
          return new Ok([state$1, Option$None$const, Option$None$const]);
        } else {
          let pending = new PendingOperation(
            PendingKind$PendingVolunteer$const,
            next_message_id,
          );
          let state$2 = add_pending(state$1, task_id, pending);
          return new Ok(
            [state$2, new Some(new Volunteer(task_id)), new Some(pending)],
          );
        }
      } else {
        let pending = new PendingOperation(
          PendingKind$PendingVolunteer$const,
          next_message_id,
        );
        let state$2 = add_pending(state$1, task_id, pending);
        return new Ok(
          [state$2, new Some(new Volunteer(task_id)), new Some(pending)],
        );
      }
    } else if (operation instanceof Abandon) {
      return new Ok([state$1, Option$None$const, Option$None$const]);
    } else {
      return new Ok([state$1, Option$None$const, Option$None$const]);
    }
  } else {
    let detail = $[0];
    return new Error(new UnexpectedResubmit(operation, detail));
  }
}

function pop_latest_pending(state, task_id, kind, message_id) {
  let $ = $dict.get(state.pending, task_id);
  if ($ instanceof Ok) {
    let $1 = $[0];
    if ($1 instanceof $Empty) {
      return new Error(("no pending op for task \"" + task_id) + "\"");
    } else {
      let operations = $1;
      let reversed = $list.reverse(operations);
      if (reversed instanceof $Empty) {
        return new Error(("no pending op for task \"" + task_id) + "\"");
      } else {
        let rest = reversed.tail;
        let found_kind = reversed.head.kind;
        let found_id = reversed.head.message_id;
        let $2 = (isEqual(found_kind, kind)) && (found_id === message_id);
        if ($2) {
          return new Ok(set_pending(state, task_id, $list.reverse(rest)));
        } else {
          return new Error("latest pending op did not match");
        }
      }
    }
  } else {
    return new Error(("no pending op for task \"" + task_id) + "\"");
  }
}

export function rollback(state, operation, message_id) {
  let task_id = operation_task_id(operation);
  let $ = pop_latest_pending(
    state,
    task_id,
    operation_pending_kind(operation),
    message_id,
  );
  if ($ instanceof Ok) {
    let state$1 = $[0];
    return new Ok([state$1, toList([new RolledBack(task_id)])]);
  } else {
    let detail = $[0];
    return new Error(new UnexpectedRollback(operation, detail));
  }
}

export function apply_stashed_operation(state, _) {
  return [state, Option$None$const];
}
