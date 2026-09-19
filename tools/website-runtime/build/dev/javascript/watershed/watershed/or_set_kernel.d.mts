import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $or_set from "../../lattice_sets/lattice_sets/or_set.d.mts";
import type * as _ from "../gleam.d.mts";

export class OrSetState extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    sequenced: $or_set.ORSet$<string>,
    optimistic: $or_set.ORSet$<string>,
    pending: _.List<PendingOperation$>,
    next_pending_message_id: number
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  sequenced: $or_set.ORSet$<string>;
  /** @deprecated */
  optimistic: $or_set.ORSet$<string>;
  /** @deprecated */
  pending: _.List<PendingOperation$>;
  /** @deprecated */
  next_pending_message_id: number;
}
export function OrSetState$OrSetState(
  replica_id: $replica_id.ReplicaId$,
  sequenced: $or_set.ORSet$<string>,
  optimistic: $or_set.ORSet$<string>,
  pending: _.List<PendingOperation$>,
  next_pending_message_id: number,
): OrSetState$;
export function OrSetState$isOrSetState(value: any): value is OrSetState$;
export function OrSetState$OrSetState$0(value: OrSetState$): $replica_id.ReplicaId$;
export function OrSetState$OrSetState$replica_id(
  value: OrSetState$,
): $replica_id.ReplicaId$;
export function OrSetState$OrSetState$1(value: OrSetState$): $or_set.ORSet$<
  string
>;
export function OrSetState$OrSetState$sequenced(value: OrSetState$): $or_set.ORSet$<
  string
>;
export function OrSetState$OrSetState$2(value: OrSetState$): $or_set.ORSet$<
  string
>;
export function OrSetState$OrSetState$optimistic(value: OrSetState$): $or_set.ORSet$<
  string
>;
export function OrSetState$OrSetState$3(value: OrSetState$): _.List<
  PendingOperation$
>;
export function OrSetState$OrSetState$pending(value: OrSetState$): _.List<
  PendingOperation$
>;
export function OrSetState$OrSetState$4(value: OrSetState$): number;
export function OrSetState$OrSetState$next_pending_message_id(value: OrSetState$): number;

export type OrSetState$ = OrSetState;

export class PendingOperation extends _.CustomType {
  /** @deprecated */
  constructor(operation: OrSetOperation$, message_id: number);
  /** @deprecated */
  operation: OrSetOperation$;
  /** @deprecated */
  message_id: number;
}
export function PendingOperation$PendingOperation(
  operation: OrSetOperation$,
  message_id: number,
): PendingOperation$;
export function PendingOperation$isPendingOperation(
  value: any,
): value is PendingOperation$;
export function PendingOperation$PendingOperation$0(value: PendingOperation$): OrSetOperation$;
export function PendingOperation$PendingOperation$operation(
  value: PendingOperation$,
): OrSetOperation$;
export function PendingOperation$PendingOperation$1(value: PendingOperation$): number;
export function PendingOperation$PendingOperation$message_id(
  value: PendingOperation$,
): number;

export type PendingOperation$ = PendingOperation;

export class Add extends _.CustomType {
  /** @deprecated */
  constructor(element: string, delta: $or_set.ORSet$<string>);
  /** @deprecated */
  element: string;
  /** @deprecated */
  delta: $or_set.ORSet$<string>;
}
export function OrSetOperation$Add(
  element: string,
  delta: $or_set.ORSet$<string>,
): OrSetOperation$;
export function OrSetOperation$isAdd(value: any): value is OrSetOperation$;
export function OrSetOperation$Add$0(value: OrSetOperation$): string;
export function OrSetOperation$Add$element(value: OrSetOperation$): string;
export function OrSetOperation$Add$1(value: OrSetOperation$): $or_set.ORSet$<
  string
>;
export function OrSetOperation$Add$delta(value: OrSetOperation$): $or_set.ORSet$<
  string
>;

export class Remove extends _.CustomType {
  /** @deprecated */
  constructor(element: string, delta: $or_set.ORSet$<string>);
  /** @deprecated */
  element: string;
  /** @deprecated */
  delta: $or_set.ORSet$<string>;
}
export function OrSetOperation$Remove(
  element: string,
  delta: $or_set.ORSet$<string>,
): OrSetOperation$;
export function OrSetOperation$isRemove(value: any): value is OrSetOperation$;
export function OrSetOperation$Remove$0(value: OrSetOperation$): string;
export function OrSetOperation$Remove$element(value: OrSetOperation$): string;
export function OrSetOperation$Remove$1(value: OrSetOperation$): $or_set.ORSet$<
  string
>;
export function OrSetOperation$Remove$delta(value: OrSetOperation$): $or_set.ORSet$<
  string
>;

export type OrSetOperation$ = Add | Remove;

export function OrSetOperation$delta(
  value: OrSetOperation$,
): $or_set.ORSet$<string>;
export function OrSetOperation$element(value: OrSetOperation$): string;

export class ElementAdded extends _.CustomType {
  /** @deprecated */
  constructor(element: string);
  /** @deprecated */
  element: string;
}
export function OrSetEvent$ElementAdded(element: string): OrSetEvent$;
export function OrSetEvent$isElementAdded(value: any): value is OrSetEvent$;
export function OrSetEvent$ElementAdded$0(value: OrSetEvent$): string;
export function OrSetEvent$ElementAdded$element(value: OrSetEvent$): string;

export class ElementRemoved extends _.CustomType {
  /** @deprecated */
  constructor(element: string);
  /** @deprecated */
  element: string;
}
export function OrSetEvent$ElementRemoved(element: string): OrSetEvent$;
export function OrSetEvent$isElementRemoved(value: any): value is OrSetEvent$;
export function OrSetEvent$ElementRemoved$0(value: OrSetEvent$): string;
export function OrSetEvent$ElementRemoved$element(value: OrSetEvent$): string;

export type OrSetEvent$ = ElementAdded | ElementRemoved;

export function OrSetEvent$element(value: OrSetEvent$): string;

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

export function new$(replica_id: $replica_id.ReplicaId$): OrSetState$;

export function contains(state: OrSetState$, element: string): boolean;

export function values(state: OrSetState$): _.List<string>;

export function sequenced_values(state: OrSetState$): _.List<string>;

export function add(state: OrSetState$, element: string): [
  OrSetState$,
  _.List<OrSetEvent$>,
  OrSetOperation$,
  number
];

export function remove(state: OrSetState$, element: string): [
  OrSetState$,
  _.List<OrSetEvent$>,
  OrSetOperation$,
  number
];

export function p2p_add(state: OrSetState$, element: string): [
  OrSetState$,
  _.List<OrSetEvent$>,
  OrSetOperation$
];

export function p2p_remove(state: OrSetState$, element: string): [
  OrSetState$,
  _.List<OrSetEvent$>,
  OrSetOperation$
];

export function p2p_merge(state: OrSetState$, other: $or_set.ORSet$<string>): [
  OrSetState$,
  _.List<OrSetEvent$>
];

export function apply_remote(state: OrSetState$, operation: OrSetOperation$): [
  OrSetState$,
  _.List<OrSetEvent$>
];

export function ack_local(state: OrSetState$, operation: OrSetOperation$): _.Result<
  OrSetState$,
  KernelError$
>;

export function ack_local_with_message_id(
  state: OrSetState$,
  operation: OrSetOperation$,
  message_id: number
): _.Result<OrSetState$, KernelError$>;

export function rollback(
  state: OrSetState$,
  operation: OrSetOperation$,
  message_id: number
): _.Result<[OrSetState$, _.List<OrSetEvent$>], KernelError$>;

export function apply_stashed_operation(
  state: OrSetState$,
  operation: OrSetOperation$
): [OrSetState$, _.List<OrSetEvent$>, OrSetOperation$, number];

export function promote_attach(state: OrSetState$): OrSetState$;

export function summary(state: OrSetState$): $json.Json$;

export function from_sequenced(
  sequenced: $or_set.ORSet$<string>,
  replica_id: $replica_id.ReplicaId$
): OrSetState$;

export function from_summary(
  summary_json: string,
  replica_id: $replica_id.ReplicaId$
): _.Result<OrSetState$, $json.DecodeError$>;

export function check_cache_coherence(state: OrSetState$): _.Result<
  undefined,
  string
>;
