import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class TaskManagerState extends _.CustomType {
  /** @deprecated */
  constructor(
    queues: $dict.Dict$<string, _.List<number>>,
    pending: $dict.Dict$<string, _.List<PendingOperation$>>
  );
  /** @deprecated */
  queues: $dict.Dict$<string, _.List<number>>;
  /** @deprecated */
  pending: $dict.Dict$<string, _.List<PendingOperation$>>;
}
export function TaskManagerState$TaskManagerState(
  queues: $dict.Dict$<string, _.List<number>>,
  pending: $dict.Dict$<string, _.List<PendingOperation$>>,
): TaskManagerState$;
export function TaskManagerState$isTaskManagerState(
  value: any,
): value is TaskManagerState$;
export function TaskManagerState$TaskManagerState$0(value: TaskManagerState$): $dict.Dict$<
  string,
  _.List<number>
>;
export function TaskManagerState$TaskManagerState$queues(value: TaskManagerState$): $dict.Dict$<
  string,
  _.List<number>
>;
export function TaskManagerState$TaskManagerState$1(value: TaskManagerState$): $dict.Dict$<
  string,
  _.List<PendingOperation$>
>;
export function TaskManagerState$TaskManagerState$pending(value: TaskManagerState$): $dict.Dict$<
  string,
  _.List<PendingOperation$>
>;

export type TaskManagerState$ = TaskManagerState;

export class Volunteer extends _.CustomType {
  /** @deprecated */
  constructor(task_id: string);
  /** @deprecated */
  task_id: string;
}
export function TaskManagerOperation$Volunteer(
  task_id: string,
): TaskManagerOperation$;
export function TaskManagerOperation$isVolunteer(
  value: any,
): value is TaskManagerOperation$;
export function TaskManagerOperation$Volunteer$0(value: TaskManagerOperation$): string;
export function TaskManagerOperation$Volunteer$task_id(
  value: TaskManagerOperation$,
): string;

export class Abandon extends _.CustomType {
  /** @deprecated */
  constructor(task_id: string);
  /** @deprecated */
  task_id: string;
}
export function TaskManagerOperation$Abandon(
  task_id: string,
): TaskManagerOperation$;
export function TaskManagerOperation$isAbandon(
  value: any,
): value is TaskManagerOperation$;
export function TaskManagerOperation$Abandon$0(value: TaskManagerOperation$): string;
export function TaskManagerOperation$Abandon$task_id(
  value: TaskManagerOperation$,
): string;

export class Complete extends _.CustomType {
  /** @deprecated */
  constructor(task_id: string);
  /** @deprecated */
  task_id: string;
}
export function TaskManagerOperation$Complete(
  task_id: string,
): TaskManagerOperation$;
export function TaskManagerOperation$isComplete(
  value: any,
): value is TaskManagerOperation$;
export function TaskManagerOperation$Complete$0(value: TaskManagerOperation$): string;
export function TaskManagerOperation$Complete$task_id(
  value: TaskManagerOperation$,
): string;

export type TaskManagerOperation$ = Volunteer | Abandon | Complete;

export function TaskManagerOperation$task_id(
  value: TaskManagerOperation$,
): string;

export class PendingOperation extends _.CustomType {
  /** @deprecated */
  constructor(kind: PendingKind$, message_id: number);
  /** @deprecated */
  kind: PendingKind$;
  /** @deprecated */
  message_id: number;
}
export function PendingOperation$PendingOperation(
  kind: PendingKind$,
  message_id: number,
): PendingOperation$;
export function PendingOperation$isPendingOperation(
  value: any,
): value is PendingOperation$;
export function PendingOperation$PendingOperation$0(value: PendingOperation$): PendingKind$;
export function PendingOperation$PendingOperation$kind(
  value: PendingOperation$,
): PendingKind$;
export function PendingOperation$PendingOperation$1(value: PendingOperation$): number;
export function PendingOperation$PendingOperation$message_id(
  value: PendingOperation$,
): number;

export type PendingOperation$ = PendingOperation;

export class PendingVolunteer extends _.CustomType {}
export function PendingKind$PendingVolunteer(): PendingKind$;
export function PendingKind$isPendingVolunteer(
  value: any,
): value is PendingKind$;

export class PendingAbandon extends _.CustomType {}
export function PendingKind$PendingAbandon(): PendingKind$;
export function PendingKind$isPendingAbandon(value: any): value is PendingKind$;

export class PendingComplete extends _.CustomType {}
export function PendingKind$PendingComplete(): PendingKind$;
export function PendingKind$isPendingComplete(
  value: any,
): value is PendingKind$;

export type PendingKind$ = PendingVolunteer | PendingAbandon | PendingComplete;

export class QueueChanged extends _.CustomType {
  /** @deprecated */
  constructor(
    task_id: string,
    old_assignee: $option.Option$<number>,
    new_assignee: $option.Option$<number>
  );
  /** @deprecated */
  task_id: string;
  /** @deprecated */
  old_assignee: $option.Option$<number>;
  /** @deprecated */
  new_assignee: $option.Option$<number>;
}
export function TaskManagerEvent$QueueChanged(
  task_id: string,
  old_assignee: $option.Option$<number>,
  new_assignee: $option.Option$<number>,
): TaskManagerEvent$;
export function TaskManagerEvent$isQueueChanged(
  value: any,
): value is TaskManagerEvent$;
export function TaskManagerEvent$QueueChanged$0(value: TaskManagerEvent$): string;
export function TaskManagerEvent$QueueChanged$task_id(
  value: TaskManagerEvent$,
): string;
export function TaskManagerEvent$QueueChanged$1(value: TaskManagerEvent$): $option.Option$<
  number
>;
export function TaskManagerEvent$QueueChanged$old_assignee(value: TaskManagerEvent$): $option.Option$<
  number
>;
export function TaskManagerEvent$QueueChanged$2(value: TaskManagerEvent$): $option.Option$<
  number
>;
export function TaskManagerEvent$QueueChanged$new_assignee(value: TaskManagerEvent$): $option.Option$<
  number
>;

export class Assigned extends _.CustomType {
  /** @deprecated */
  constructor(task_id: string);
  /** @deprecated */
  task_id: string;
}
export function TaskManagerEvent$Assigned(task_id: string): TaskManagerEvent$;
export function TaskManagerEvent$isAssigned(
  value: any,
): value is TaskManagerEvent$;
export function TaskManagerEvent$Assigned$0(value: TaskManagerEvent$): string;
export function TaskManagerEvent$Assigned$task_id(value: TaskManagerEvent$): string;

export class Lost extends _.CustomType {
  /** @deprecated */
  constructor(task_id: string);
  /** @deprecated */
  task_id: string;
}
export function TaskManagerEvent$Lost(task_id: string): TaskManagerEvent$;
export function TaskManagerEvent$isLost(value: any): value is TaskManagerEvent$;
export function TaskManagerEvent$Lost$0(value: TaskManagerEvent$): string;
export function TaskManagerEvent$Lost$task_id(value: TaskManagerEvent$): string;

export class Completed extends _.CustomType {
  /** @deprecated */
  constructor(task_id: string);
  /** @deprecated */
  task_id: string;
}
export function TaskManagerEvent$Completed(task_id: string): TaskManagerEvent$;
export function TaskManagerEvent$isCompleted(
  value: any,
): value is TaskManagerEvent$;
export function TaskManagerEvent$Completed$0(value: TaskManagerEvent$): string;
export function TaskManagerEvent$Completed$task_id(value: TaskManagerEvent$): string;

export class Abandoned extends _.CustomType {
  /** @deprecated */
  constructor(task_id: string);
  /** @deprecated */
  task_id: string;
}
export function TaskManagerEvent$Abandoned(task_id: string): TaskManagerEvent$;
export function TaskManagerEvent$isAbandoned(
  value: any,
): value is TaskManagerEvent$;
export function TaskManagerEvent$Abandoned$0(value: TaskManagerEvent$): string;
export function TaskManagerEvent$Abandoned$task_id(value: TaskManagerEvent$): string;

export class RolledBack extends _.CustomType {
  /** @deprecated */
  constructor(task_id: string);
  /** @deprecated */
  task_id: string;
}
export function TaskManagerEvent$RolledBack(task_id: string): TaskManagerEvent$;
export function TaskManagerEvent$isRolledBack(
  value: any,
): value is TaskManagerEvent$;
export function TaskManagerEvent$RolledBack$0(value: TaskManagerEvent$): string;
export function TaskManagerEvent$RolledBack$task_id(value: TaskManagerEvent$): string;

export type TaskManagerEvent$ = QueueChanged | Assigned | Lost | Completed | Abandoned | RolledBack;

export function TaskManagerEvent$task_id(value: TaskManagerEvent$): string;

export class AssignedNow extends _.CustomType {}
export function VolunteerOutcome$AssignedNow(): VolunteerOutcome$;
export function VolunteerOutcome$isAssignedNow(
  value: any,
): value is VolunteerOutcome$;

export class Waiting extends _.CustomType {}
export function VolunteerOutcome$Waiting(): VolunteerOutcome$;
export function VolunteerOutcome$isWaiting(
  value: any,
): value is VolunteerOutcome$;

export class CompletedBeforeAssignment extends _.CustomType {}
export function VolunteerOutcome$CompletedBeforeAssignment(): VolunteerOutcome$;
export function VolunteerOutcome$isCompletedBeforeAssignment(
  value: any,
): value is VolunteerOutcome$;

export class AbandonedBeforeAssignment extends _.CustomType {}
export function VolunteerOutcome$AbandonedBeforeAssignment(): VolunteerOutcome$;
export function VolunteerOutcome$isAbandonedBeforeAssignment(
  value: any,
): value is VolunteerOutcome$;

export class DisconnectedBeforeAssignment extends _.CustomType {}
export function VolunteerOutcome$DisconnectedBeforeAssignment(
  
): VolunteerOutcome$;
export function VolunteerOutcome$isDisconnectedBeforeAssignment(
  value: any,
): value is VolunteerOutcome$;

export class RolledBackBeforeAssignment extends _.CustomType {}
export function VolunteerOutcome$RolledBackBeforeAssignment(
  
): VolunteerOutcome$;
export function VolunteerOutcome$isRolledBackBeforeAssignment(
  value: any,
): value is VolunteerOutcome$;

export type VolunteerOutcome$ = AssignedNow | Waiting | CompletedBeforeAssignment | AbandonedBeforeAssignment | DisconnectedBeforeAssignment | RolledBackBeforeAssignment;

export class NotAssigned extends _.CustomType {
  /** @deprecated */
  constructor(task_id: string);
  /** @deprecated */
  task_id: string;
}
export function TaskManagerError$NotAssigned(
  task_id: string,
): TaskManagerError$;
export function TaskManagerError$isNotAssigned(
  value: any,
): value is TaskManagerError$;
export function TaskManagerError$NotAssigned$0(value: TaskManagerError$): string;
export function TaskManagerError$NotAssigned$task_id(
  value: TaskManagerError$,
): string;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(operation: TaskManagerOperation$, detail: string);
  /** @deprecated */
  operation: TaskManagerOperation$;
  /** @deprecated */
  detail: string;
}
export function TaskManagerError$UnexpectedAck(
  operation: TaskManagerOperation$,
  detail: string,
): TaskManagerError$;
export function TaskManagerError$isUnexpectedAck(
  value: any,
): value is TaskManagerError$;
export function TaskManagerError$UnexpectedAck$0(value: TaskManagerError$): TaskManagerOperation$;
export function TaskManagerError$UnexpectedAck$operation(
  value: TaskManagerError$,
): TaskManagerOperation$;
export function TaskManagerError$UnexpectedAck$1(value: TaskManagerError$): string;
export function TaskManagerError$UnexpectedAck$detail(
  value: TaskManagerError$,
): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(operation: TaskManagerOperation$, detail: string);
  /** @deprecated */
  operation: TaskManagerOperation$;
  /** @deprecated */
  detail: string;
}
export function TaskManagerError$UnexpectedRollback(
  operation: TaskManagerOperation$,
  detail: string,
): TaskManagerError$;
export function TaskManagerError$isUnexpectedRollback(
  value: any,
): value is TaskManagerError$;
export function TaskManagerError$UnexpectedRollback$0(value: TaskManagerError$): TaskManagerOperation$;
export function TaskManagerError$UnexpectedRollback$operation(
  value: TaskManagerError$,
): TaskManagerOperation$;
export function TaskManagerError$UnexpectedRollback$1(value: TaskManagerError$): string;
export function TaskManagerError$UnexpectedRollback$detail(
  value: TaskManagerError$,
): string;

export class UnexpectedResubmit extends _.CustomType {
  /** @deprecated */
  constructor(operation: TaskManagerOperation$, detail: string);
  /** @deprecated */
  operation: TaskManagerOperation$;
  /** @deprecated */
  detail: string;
}
export function TaskManagerError$UnexpectedResubmit(
  operation: TaskManagerOperation$,
  detail: string,
): TaskManagerError$;
export function TaskManagerError$isUnexpectedResubmit(
  value: any,
): value is TaskManagerError$;
export function TaskManagerError$UnexpectedResubmit$0(value: TaskManagerError$): TaskManagerOperation$;
export function TaskManagerError$UnexpectedResubmit$operation(
  value: TaskManagerError$,
): TaskManagerOperation$;
export function TaskManagerError$UnexpectedResubmit$1(value: TaskManagerError$): string;
export function TaskManagerError$UnexpectedResubmit$detail(
  value: TaskManagerError$,
): string;

export type TaskManagerError$ = NotAssigned | UnexpectedAck | UnexpectedRollback | UnexpectedResubmit;

export function new$(): TaskManagerState$;

export function from_summary(queues: _.List<[string, _.List<number>]>): TaskManagerState$;

export function summary_queues(state: TaskManagerState$): _.List<
  [string, _.List<number>]
>;

export function assigned(
  state: TaskManagerState$,
  task_id: string,
  self_id: number,
  connected: boolean
): boolean;

export function queued(
  state: TaskManagerState$,
  task_id: string,
  self_id: number,
  connected: boolean
): boolean;

export function queued_optimistically(
  state: TaskManagerState$,
  task_id: string,
  self_id: number
): boolean;

export function volunteer(
  state: TaskManagerState$,
  task_id: string,
  self_id: number,
  message_id: number
): [
  TaskManagerState$,
  $option.Option$<TaskManagerOperation$>,
  VolunteerOutcome$
];

export function volunteer_detached(
  state: TaskManagerState$,
  task_id: string,
  self_id: number
): [TaskManagerState$, _.List<TaskManagerEvent$>, VolunteerOutcome$];

export function abandon(
  state: TaskManagerState$,
  task_id: string,
  self_id: number,
  message_id: number
): [
  TaskManagerState$,
  $option.Option$<TaskManagerOperation$>,
  _.List<TaskManagerEvent$>
];

export function abandon_detached(
  state: TaskManagerState$,
  task_id: string,
  self_id: number
): [TaskManagerState$, _.List<TaskManagerEvent$>];

export function complete(
  state: TaskManagerState$,
  task_id: string,
  self_id: number,
  message_id: number
): _.Result<[TaskManagerState$, TaskManagerOperation$], TaskManagerError$>;

export function complete_detached(state: TaskManagerState$, task_id: string): [
  TaskManagerState$,
  _.List<TaskManagerEvent$>
];

export function apply_remote(
  state: TaskManagerState$,
  operation: TaskManagerOperation$,
  author: number,
  roster: _.List<number>
): [TaskManagerState$, _.List<TaskManagerEvent$>];

export function ack_local(
  state: TaskManagerState$,
  operation: TaskManagerOperation$,
  author: number,
  message_id: number,
  roster: _.List<number>
): _.Result<[TaskManagerState$, _.List<TaskManagerEvent$>], TaskManagerError$>;

export function remove_client(state: TaskManagerState$, client_id: number): [
  TaskManagerState$,
  _.List<TaskManagerEvent$>
];

export function on_disconnect(state: TaskManagerState$, self_id: number): [
  TaskManagerState$,
  _.List<TaskManagerEvent$>
];

export function replace_placeholder(
  state: TaskManagerState$,
  placeholder: number,
  real_id: number
): TaskManagerState$;

export function scrub_not_in_roster(
  state: TaskManagerState$,
  roster: _.List<number>
): [TaskManagerState$, _.List<TaskManagerEvent$>];

export function resubmit(
  state: TaskManagerState$,
  operation: TaskManagerOperation$,
  message_id: number,
  next_message_id: number
): _.Result<
  [
    TaskManagerState$,
    $option.Option$<TaskManagerOperation$>,
    $option.Option$<PendingOperation$>
  ],
  TaskManagerError$
>;

export function rollback(
  state: TaskManagerState$,
  operation: TaskManagerOperation$,
  message_id: number
): _.Result<[TaskManagerState$, _.List<TaskManagerEvent$>], TaskManagerError$>;

export function apply_stashed_operation(
  state: TaskManagerState$,
  x1: TaskManagerOperation$
): [TaskManagerState$, $option.Option$<TaskManagerOperation$>];
