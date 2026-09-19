import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class OrderedState extends _.CustomType {
  /** @deprecated */
  constructor(queue: _.List<$json.Json$>, jobs: $dict.Dict$<string, JobEntry$>);
  /** @deprecated */
  queue: _.List<$json.Json$>;
  /** @deprecated */
  jobs: $dict.Dict$<string, JobEntry$>;
}
export function OrderedState$OrderedState(
  queue: _.List<$json.Json$>,
  jobs: $dict.Dict$<string, JobEntry$>,
): OrderedState$;
export function OrderedState$isOrderedState(value: any): value is OrderedState$;
export function OrderedState$OrderedState$0(value: OrderedState$): _.List<
  $json.Json$
>;
export function OrderedState$OrderedState$queue(value: OrderedState$): _.List<
  $json.Json$
>;
export function OrderedState$OrderedState$1(value: OrderedState$): $dict.Dict$<
  string,
  JobEntry$
>;
export function OrderedState$OrderedState$jobs(value: OrderedState$): $dict.Dict$<
  string,
  JobEntry$
>;

export type OrderedState$ = OrderedState;

export class JobEntry extends _.CustomType {
  /** @deprecated */
  constructor(value: $json.Json$, owner: $option.Option$<number>);
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  owner: $option.Option$<number>;
}
export function JobEntry$JobEntry(
  value: $json.Json$,
  owner: $option.Option$<number>,
): JobEntry$;
export function JobEntry$isJobEntry(value: any): value is JobEntry$;
export function JobEntry$JobEntry$0(value: JobEntry$): $json.Json$;
export function JobEntry$JobEntry$value(value: JobEntry$): $json.Json$;
export function JobEntry$JobEntry$1(value: JobEntry$): $option.Option$<number>;
export function JobEntry$JobEntry$owner(value: JobEntry$): $option.Option$<
  number
>;

export type JobEntry$ = JobEntry;

export class Add extends _.CustomType {
  /** @deprecated */
  constructor(value: $json.Json$);
  /** @deprecated */
  value: $json.Json$;
}
export function OrderedOperation$Add(value: $json.Json$): OrderedOperation$;
export function OrderedOperation$isAdd(value: any): value is OrderedOperation$;
export function OrderedOperation$Add$0(value: OrderedOperation$): $json.Json$;
export function OrderedOperation$Add$value(value: OrderedOperation$): $json.Json$;

export class Acquire extends _.CustomType {
  /** @deprecated */
  constructor(acquire_id: string);
  /** @deprecated */
  acquire_id: string;
}
export function OrderedOperation$Acquire(acquire_id: string): OrderedOperation$;
export function OrderedOperation$isAcquire(
  value: any,
): value is OrderedOperation$;
export function OrderedOperation$Acquire$0(value: OrderedOperation$): string;
export function OrderedOperation$Acquire$acquire_id(value: OrderedOperation$): string;

export class Complete extends _.CustomType {
  /** @deprecated */
  constructor(acquire_id: string);
  /** @deprecated */
  acquire_id: string;
}
export function OrderedOperation$Complete(
  acquire_id: string,
): OrderedOperation$;
export function OrderedOperation$isComplete(
  value: any,
): value is OrderedOperation$;
export function OrderedOperation$Complete$0(value: OrderedOperation$): string;
export function OrderedOperation$Complete$acquire_id(value: OrderedOperation$): string;

export class Release extends _.CustomType {
  /** @deprecated */
  constructor(acquire_id: string);
  /** @deprecated */
  acquire_id: string;
}
export function OrderedOperation$Release(acquire_id: string): OrderedOperation$;
export function OrderedOperation$isRelease(
  value: any,
): value is OrderedOperation$;
export function OrderedOperation$Release$0(value: OrderedOperation$): string;
export function OrderedOperation$Release$acquire_id(value: OrderedOperation$): string;

export type OrderedOperation$ = Add | Acquire | Complete | Release;

export class Added extends _.CustomType {
  /** @deprecated */
  constructor(value: $json.Json$, newly_added: boolean, local: boolean);
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  newly_added: boolean;
  /** @deprecated */
  local: boolean;
}
export function OrderedEvent$Added(
  value: $json.Json$,
  newly_added: boolean,
  local: boolean,
): OrderedEvent$;
export function OrderedEvent$isAdded(value: any): value is OrderedEvent$;
export function OrderedEvent$Added$0(value: OrderedEvent$): $json.Json$;
export function OrderedEvent$Added$value(value: OrderedEvent$): $json.Json$;
export function OrderedEvent$Added$1(value: OrderedEvent$): boolean;
export function OrderedEvent$Added$newly_added(value: OrderedEvent$): boolean;
export function OrderedEvent$Added$2(value: OrderedEvent$): boolean;
export function OrderedEvent$Added$local(value: OrderedEvent$): boolean;

export class Acquired extends _.CustomType {
  /** @deprecated */
  constructor(
    value: $json.Json$,
    owner: $option.Option$<number>,
    local: boolean
  );
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  owner: $option.Option$<number>;
  /** @deprecated */
  local: boolean;
}
export function OrderedEvent$Acquired(
  value: $json.Json$,
  owner: $option.Option$<number>,
  local: boolean,
): OrderedEvent$;
export function OrderedEvent$isAcquired(value: any): value is OrderedEvent$;
export function OrderedEvent$Acquired$0(value: OrderedEvent$): $json.Json$;
export function OrderedEvent$Acquired$value(value: OrderedEvent$): $json.Json$;
export function OrderedEvent$Acquired$1(value: OrderedEvent$): $option.Option$<
  number
>;
export function OrderedEvent$Acquired$owner(value: OrderedEvent$): $option.Option$<
  number
>;
export function OrderedEvent$Acquired$2(value: OrderedEvent$): boolean;
export function OrderedEvent$Acquired$local(value: OrderedEvent$): boolean;

export class Completed extends _.CustomType {
  /** @deprecated */
  constructor(value: $json.Json$, local: boolean);
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  local: boolean;
}
export function OrderedEvent$Completed(
  value: $json.Json$,
  local: boolean,
): OrderedEvent$;
export function OrderedEvent$isCompleted(value: any): value is OrderedEvent$;
export function OrderedEvent$Completed$0(value: OrderedEvent$): $json.Json$;
export function OrderedEvent$Completed$value(value: OrderedEvent$): $json.Json$;
export function OrderedEvent$Completed$1(value: OrderedEvent$): boolean;
export function OrderedEvent$Completed$local(value: OrderedEvent$): boolean;

export class LocalReleased extends _.CustomType {
  /** @deprecated */
  constructor(value: $json.Json$, intentional: boolean);
  /** @deprecated */
  value: $json.Json$;
  /** @deprecated */
  intentional: boolean;
}
export function OrderedEvent$LocalReleased(
  value: $json.Json$,
  intentional: boolean,
): OrderedEvent$;
export function OrderedEvent$isLocalReleased(
  value: any,
): value is OrderedEvent$;
export function OrderedEvent$LocalReleased$0(value: OrderedEvent$): $json.Json$;
export function OrderedEvent$LocalReleased$value(value: OrderedEvent$): $json.Json$;
export function OrderedEvent$LocalReleased$1(
  value: OrderedEvent$,
): boolean;
export function OrderedEvent$LocalReleased$intentional(value: OrderedEvent$): boolean;

export type OrderedEvent$ = Added | Acquired | Completed | LocalReleased;

export function OrderedEvent$value(value: OrderedEvent$): $json.Json$;

export class AcquiredItem extends _.CustomType {
  /** @deprecated */
  constructor(acquire_id: string, value: $json.Json$);
  /** @deprecated */
  acquire_id: string;
  /** @deprecated */
  value: $json.Json$;
}
export function AcquireOutcome$AcquiredItem(
  acquire_id: string,
  value: $json.Json$,
): AcquireOutcome$;
export function AcquireOutcome$isAcquiredItem(
  value: any,
): value is AcquireOutcome$;
export function AcquireOutcome$AcquiredItem$0(value: AcquireOutcome$): string;
export function AcquireOutcome$AcquiredItem$acquire_id(value: AcquireOutcome$): string;
export function AcquireOutcome$AcquiredItem$1(
  value: AcquireOutcome$,
): $json.Json$;
export function AcquireOutcome$AcquiredItem$value(value: AcquireOutcome$): $json.Json$;

export class QueueEmpty extends _.CustomType {}
export function AcquireOutcome$QueueEmpty(): AcquireOutcome$;
export function AcquireOutcome$isQueueEmpty(
  value: any,
): value is AcquireOutcome$;

export class Aborted extends _.CustomType {}
export function AcquireOutcome$Aborted(): AcquireOutcome$;
export function AcquireOutcome$isAborted(value: any): value is AcquireOutcome$;

export type AcquireOutcome$ = AcquiredItem | QueueEmpty | Aborted;

export function new$(): OrderedState$;

export function from_summary(
  queue: _.List<$json.Json$>,
  jobs: _.List<[string, JobEntry$]>
): OrderedState$;

export function summary_queue(state: OrderedState$): _.List<$json.Json$>;

export function summary_jobs(state: OrderedState$): _.List<[string, JobEntry$]>;

export function size(state: OrderedState$): number;

export function add(x0: OrderedState$, value: $json.Json$): OrderedOperation$;

export function acquire(acquire_id: string): OrderedOperation$;

export function complete(acquire_id: string): OrderedOperation$;

export function release(acquire_id: string): OrderedOperation$;

export function add_detached(state: OrderedState$, value: $json.Json$): [
  OrderedState$,
  _.List<OrderedEvent$>
];

export function ack_local_acquire(
  state: OrderedState$,
  acquire_id: string,
  author: $option.Option$<number>
): [OrderedState$, _.List<OrderedEvent$>, AcquireOutcome$];

export function acquire_detached(state: OrderedState$, acquire_id: string): [
  OrderedState$,
  _.List<OrderedEvent$>,
  AcquireOutcome$
];

export function apply_add(state: OrderedState$, value: $json.Json$): [
  OrderedState$,
  _.List<OrderedEvent$>
];

export function apply_acquire(
  state: OrderedState$,
  acquire_id: string,
  author: $option.Option$<number>
): [OrderedState$, _.List<OrderedEvent$>, $option.Option$<$json.Json$>];

export function apply_complete(state: OrderedState$, acquire_id: string): [
  OrderedState$,
  _.List<OrderedEvent$>
];

export function apply_release(state: OrderedState$, acquire_id: string): [
  OrderedState$,
  _.List<OrderedEvent$>
];

export function apply_remote(
  state: OrderedState$,
  operation: OrderedOperation$,
  author: number
): [OrderedState$, _.List<OrderedEvent$>];

export function ack_local(
  state: OrderedState$,
  operation: OrderedOperation$,
  author: number
): [OrderedState$, _.List<OrderedEvent$>, $option.Option$<AcquireOutcome$>];

export function remove_client(
  state: OrderedState$,
  owner: $option.Option$<number>
): [OrderedState$, _.List<OrderedEvent$>];

export function on_disconnect_notify(
  state: OrderedState$,
  owner: $option.Option$<number>
): _.List<OrderedEvent$>;

export function rollback(state: OrderedState$, x1: OrderedOperation$): [
  OrderedState$,
  AcquireOutcome$
];

export function apply_stashed_operation(
  state: OrderedState$,
  operation: OrderedOperation$
): [OrderedState$, OrderedOperation$];
