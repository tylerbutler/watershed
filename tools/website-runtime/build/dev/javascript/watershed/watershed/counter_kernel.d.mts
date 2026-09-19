import type * as _ from "../gleam.d.mts";

export class CounterState extends _.CustomType {
  /** @deprecated */
  constructor(
    value: number,
    pending: _.List<PendingOperation$>,
    next_pending_message_id: number
  );
  /** @deprecated */
  value: number;
  /** @deprecated */
  pending: _.List<PendingOperation$>;
  /** @deprecated */
  next_pending_message_id: number;
}
export function CounterState$CounterState(
  value: number,
  pending: _.List<PendingOperation$>,
  next_pending_message_id: number,
): CounterState$;
export function CounterState$isCounterState(value: any): value is CounterState$;
export function CounterState$CounterState$0(value: CounterState$): number;
export function CounterState$CounterState$value(value: CounterState$): number;
export function CounterState$CounterState$1(value: CounterState$): _.List<
  PendingOperation$
>;
export function CounterState$CounterState$pending(value: CounterState$): _.List<
  PendingOperation$
>;
export function CounterState$CounterState$2(value: CounterState$): number;
export function CounterState$CounterState$next_pending_message_id(value: CounterState$): number;

export type CounterState$ = CounterState;

export class PendingIncrement extends _.CustomType {
  /** @deprecated */
  constructor(increment_amount: number, message_id: number);
  /** @deprecated */
  increment_amount: number;
  /** @deprecated */
  message_id: number;
}
export function PendingOperation$PendingIncrement(
  increment_amount: number,
  message_id: number,
): PendingOperation$;
export function PendingOperation$isPendingIncrement(
  value: any,
): value is PendingOperation$;
export function PendingOperation$PendingIncrement$0(value: PendingOperation$): number;
export function PendingOperation$PendingIncrement$increment_amount(
  value: PendingOperation$,
): number;
export function PendingOperation$PendingIncrement$1(value: PendingOperation$): number;
export function PendingOperation$PendingIncrement$message_id(
  value: PendingOperation$,
): number;

export type PendingOperation$ = PendingIncrement;

export class Increment extends _.CustomType {
  /** @deprecated */
  constructor(increment_amount: number);
  /** @deprecated */
  increment_amount: number;
}
export function CounterOperation$Increment(
  increment_amount: number,
): CounterOperation$;
export function CounterOperation$isIncrement(
  value: any,
): value is CounterOperation$;
export function CounterOperation$Increment$0(value: CounterOperation$): number;
export function CounterOperation$Increment$increment_amount(value: CounterOperation$): number;

export type CounterOperation$ = Increment;

export class Incremented extends _.CustomType {
  /** @deprecated */
  constructor(increment_amount: number, new_value: number);
  /** @deprecated */
  increment_amount: number;
  /** @deprecated */
  new_value: number;
}
export function CounterEvent$Incremented(
  increment_amount: number,
  new_value: number,
): CounterEvent$;
export function CounterEvent$isIncremented(value: any): value is CounterEvent$;
export function CounterEvent$Incremented$0(value: CounterEvent$): number;
export function CounterEvent$Incremented$increment_amount(value: CounterEvent$): number;
export function CounterEvent$Incremented$1(
  value: CounterEvent$,
): number;
export function CounterEvent$Incremented$new_value(value: CounterEvent$): number;

export type CounterEvent$ = Incremented;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(operation: CounterOperation$, detail: string);
  /** @deprecated */
  operation: CounterOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(
  operation: CounterOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): CounterOperation$;
export function KernelError$UnexpectedAck$operation(
  value: KernelError$,
): CounterOperation$;
export function KernelError$UnexpectedAck$1(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(operation: CounterOperation$, detail: string);
  /** @deprecated */
  operation: CounterOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(
  operation: CounterOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): CounterOperation$;
export function KernelError$UnexpectedRollback$operation(
  value: KernelError$,
): CounterOperation$;
export function KernelError$UnexpectedRollback$1(value: KernelError$): string;
export function KernelError$UnexpectedRollback$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAck | UnexpectedRollback;

export function KernelError$detail(value: KernelError$): string;
export function KernelError$operation(value: KernelError$): CounterOperation$;

export function new$(): CounterState$;

export function from_summary(value: number): CounterState$;

export function summary_value(state: CounterState$): number;

export function increment(state: CounterState$, increment_amount: number): [
  CounterState$,
  _.List<CounterEvent$>,
  CounterOperation$,
  number
];

export function apply_remote(state: CounterState$, operation: CounterOperation$): [
  CounterState$,
  _.List<CounterEvent$>
];

export function ack_local(state: CounterState$, operation: CounterOperation$): _.Result<
  CounterState$,
  KernelError$
>;

export function ack_local_with_message_id(
  state: CounterState$,
  operation: CounterOperation$,
  message_id: number
): _.Result<CounterState$, KernelError$>;

export function apply_stashed_operation(
  state: CounterState$,
  operation: CounterOperation$
): [CounterState$, _.List<CounterEvent$>, CounterOperation$, number];

export function rollback(
  state: CounterState$,
  operation: CounterOperation$,
  message_id: number
): _.Result<[CounterState$, _.List<CounterEvent$>], KernelError$>;
