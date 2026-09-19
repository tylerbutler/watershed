import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $two_p_set from "../../lattice_sets/lattice_sets/two_p_set.d.mts";
import type * as _ from "../gleam.d.mts";

export class TwoPSetState extends _.CustomType {
  /** @deprecated */
  constructor(
    sequenced: $two_p_set.TwoPSet$<string>,
    optimistic: $two_p_set.TwoPSet$<string>,
    pending: _.List<PendingOperation$>,
    next_pending_message_id: number
  );
  /** @deprecated */
  sequenced: $two_p_set.TwoPSet$<string>;
  /** @deprecated */
  optimistic: $two_p_set.TwoPSet$<string>;
  /** @deprecated */
  pending: _.List<PendingOperation$>;
  /** @deprecated */
  next_pending_message_id: number;
}
export function TwoPSetState$TwoPSetState(
  sequenced: $two_p_set.TwoPSet$<string>,
  optimistic: $two_p_set.TwoPSet$<string>,
  pending: _.List<PendingOperation$>,
  next_pending_message_id: number,
): TwoPSetState$;
export function TwoPSetState$isTwoPSetState(value: any): value is TwoPSetState$;
export function TwoPSetState$TwoPSetState$0(value: TwoPSetState$): $two_p_set.TwoPSet$<
  string
>;
export function TwoPSetState$TwoPSetState$sequenced(value: TwoPSetState$): $two_p_set.TwoPSet$<
  string
>;
export function TwoPSetState$TwoPSetState$1(value: TwoPSetState$): $two_p_set.TwoPSet$<
  string
>;
export function TwoPSetState$TwoPSetState$optimistic(value: TwoPSetState$): $two_p_set.TwoPSet$<
  string
>;
export function TwoPSetState$TwoPSetState$2(value: TwoPSetState$): _.List<
  PendingOperation$
>;
export function TwoPSetState$TwoPSetState$pending(value: TwoPSetState$): _.List<
  PendingOperation$
>;
export function TwoPSetState$TwoPSetState$3(value: TwoPSetState$): number;
export function TwoPSetState$TwoPSetState$next_pending_message_id(value: TwoPSetState$): number;

export type TwoPSetState$ = TwoPSetState;

export class PendingOperation extends _.CustomType {
  /** @deprecated */
  constructor(operation: TwoPSetOperation$, message_id: number);
  /** @deprecated */
  operation: TwoPSetOperation$;
  /** @deprecated */
  message_id: number;
}
export function PendingOperation$PendingOperation(
  operation: TwoPSetOperation$,
  message_id: number,
): PendingOperation$;
export function PendingOperation$isPendingOperation(
  value: any,
): value is PendingOperation$;
export function PendingOperation$PendingOperation$0(value: PendingOperation$): TwoPSetOperation$;
export function PendingOperation$PendingOperation$operation(
  value: PendingOperation$,
): TwoPSetOperation$;
export function PendingOperation$PendingOperation$1(value: PendingOperation$): number;
export function PendingOperation$PendingOperation$message_id(
  value: PendingOperation$,
): number;

export type PendingOperation$ = PendingOperation;

export class Add extends _.CustomType {
  /** @deprecated */
  constructor(element: string, delta: $two_p_set.TwoPSet$<string>);
  /** @deprecated */
  element: string;
  /** @deprecated */
  delta: $two_p_set.TwoPSet$<string>;
}
export function TwoPSetOperation$Add(
  element: string,
  delta: $two_p_set.TwoPSet$<string>,
): TwoPSetOperation$;
export function TwoPSetOperation$isAdd(value: any): value is TwoPSetOperation$;
export function TwoPSetOperation$Add$0(value: TwoPSetOperation$): string;
export function TwoPSetOperation$Add$element(value: TwoPSetOperation$): string;
export function TwoPSetOperation$Add$1(value: TwoPSetOperation$): $two_p_set.TwoPSet$<
  string
>;
export function TwoPSetOperation$Add$delta(value: TwoPSetOperation$): $two_p_set.TwoPSet$<
  string
>;

export class Remove extends _.CustomType {
  /** @deprecated */
  constructor(element: string, delta: $two_p_set.TwoPSet$<string>);
  /** @deprecated */
  element: string;
  /** @deprecated */
  delta: $two_p_set.TwoPSet$<string>;
}
export function TwoPSetOperation$Remove(
  element: string,
  delta: $two_p_set.TwoPSet$<string>,
): TwoPSetOperation$;
export function TwoPSetOperation$isRemove(
  value: any,
): value is TwoPSetOperation$;
export function TwoPSetOperation$Remove$0(value: TwoPSetOperation$): string;
export function TwoPSetOperation$Remove$element(value: TwoPSetOperation$): string;
export function TwoPSetOperation$Remove$1(
  value: TwoPSetOperation$,
): $two_p_set.TwoPSet$<string>;
export function TwoPSetOperation$Remove$delta(value: TwoPSetOperation$): $two_p_set.TwoPSet$<
  string
>;

export type TwoPSetOperation$ = Add | Remove;

export function TwoPSetOperation$delta(
  value: TwoPSetOperation$,
): $two_p_set.TwoPSet$<string>;
export function TwoPSetOperation$element(value: TwoPSetOperation$): string;

export class ElementAdded extends _.CustomType {
  /** @deprecated */
  constructor(element: string);
  /** @deprecated */
  element: string;
}
export function TwoPSetEvent$ElementAdded(element: string): TwoPSetEvent$;
export function TwoPSetEvent$isElementAdded(value: any): value is TwoPSetEvent$;
export function TwoPSetEvent$ElementAdded$0(value: TwoPSetEvent$): string;
export function TwoPSetEvent$ElementAdded$element(value: TwoPSetEvent$): string;

export class ElementRemoved extends _.CustomType {
  /** @deprecated */
  constructor(element: string);
  /** @deprecated */
  element: string;
}
export function TwoPSetEvent$ElementRemoved(element: string): TwoPSetEvent$;
export function TwoPSetEvent$isElementRemoved(
  value: any,
): value is TwoPSetEvent$;
export function TwoPSetEvent$ElementRemoved$0(value: TwoPSetEvent$): string;
export function TwoPSetEvent$ElementRemoved$element(value: TwoPSetEvent$): string;

export type TwoPSetEvent$ = ElementAdded | ElementRemoved;

export function TwoPSetEvent$element(value: TwoPSetEvent$): string;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(detail: string): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(detail: string): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): string;
export function KernelError$UnexpectedRollback$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAck | UnexpectedRollback;

export function KernelError$detail(value: KernelError$): string;

export function new$(): TwoPSetState$;

export function contains(state: TwoPSetState$, element: string): boolean;

export function values(state: TwoPSetState$): _.List<string>;

export function sequenced_values(state: TwoPSetState$): _.List<string>;

export function add(state: TwoPSetState$, element: string): [
  TwoPSetState$,
  _.List<TwoPSetEvent$>,
  TwoPSetOperation$,
  number
];

export function remove(state: TwoPSetState$, element: string): [
  TwoPSetState$,
  _.List<TwoPSetEvent$>,
  TwoPSetOperation$,
  number
];

export function p2p_add(state: TwoPSetState$, element: string): [
  TwoPSetState$,
  _.List<TwoPSetEvent$>,
  TwoPSetOperation$
];

export function p2p_remove(state: TwoPSetState$, element: string): [
  TwoPSetState$,
  _.List<TwoPSetEvent$>,
  TwoPSetOperation$
];

export function p2p_merge(
  state: TwoPSetState$,
  other: $two_p_set.TwoPSet$<string>
): [TwoPSetState$, _.List<TwoPSetEvent$>];

export function apply_remote(state: TwoPSetState$, operation: TwoPSetOperation$): [
  TwoPSetState$,
  _.List<TwoPSetEvent$>
];

export function ack_local(state: TwoPSetState$, operation: TwoPSetOperation$): _.Result<
  TwoPSetState$,
  KernelError$
>;

export function ack_local_with_message_id(
  state: TwoPSetState$,
  operation: TwoPSetOperation$,
  message_id: number
): _.Result<TwoPSetState$, KernelError$>;

export function rollback(
  state: TwoPSetState$,
  operation: TwoPSetOperation$,
  message_id: number
): _.Result<[TwoPSetState$, _.List<TwoPSetEvent$>], KernelError$>;

export function apply_stashed_operation(
  state: TwoPSetState$,
  operation: TwoPSetOperation$
): [TwoPSetState$, _.List<TwoPSetEvent$>, TwoPSetOperation$, number];

export function promote_attach(state: TwoPSetState$): TwoPSetState$;

export function summary(state: TwoPSetState$): $json.Json$;

export function from_sequenced(sequenced: $two_p_set.TwoPSet$<string>): TwoPSetState$;

export function from_summary(summary_json: string): _.Result<
  TwoPSetState$,
  $json.DecodeError$
>;

export function check_cache_coherence(state: TwoPSetState$): _.Result<
  undefined,
  string
>;
