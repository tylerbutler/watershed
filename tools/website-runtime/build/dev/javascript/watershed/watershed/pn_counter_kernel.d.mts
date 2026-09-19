import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $pn_counter from "../../lattice_counters/lattice_counters/pn_counter.d.mts";
import type * as _ from "../gleam.d.mts";

export class PnCounterState extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    sequenced: $pn_counter.PNCounter$,
    optimistic: $pn_counter.PNCounter$,
    pending: _.List<PendingDelta$>,
    next_pending_message_id: number
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  sequenced: $pn_counter.PNCounter$;
  /** @deprecated */
  optimistic: $pn_counter.PNCounter$;
  /** @deprecated */
  pending: _.List<PendingDelta$>;
  /** @deprecated */
  next_pending_message_id: number;
}
export function PnCounterState$PnCounterState(
  replica_id: $replica_id.ReplicaId$,
  sequenced: $pn_counter.PNCounter$,
  optimistic: $pn_counter.PNCounter$,
  pending: _.List<PendingDelta$>,
  next_pending_message_id: number,
): PnCounterState$;
export function PnCounterState$isPnCounterState(
  value: any,
): value is PnCounterState$;
export function PnCounterState$PnCounterState$0(value: PnCounterState$): $replica_id.ReplicaId$;
export function PnCounterState$PnCounterState$replica_id(
  value: PnCounterState$,
): $replica_id.ReplicaId$;
export function PnCounterState$PnCounterState$1(value: PnCounterState$): $pn_counter.PNCounter$;
export function PnCounterState$PnCounterState$sequenced(
  value: PnCounterState$,
): $pn_counter.PNCounter$;
export function PnCounterState$PnCounterState$2(value: PnCounterState$): $pn_counter.PNCounter$;
export function PnCounterState$PnCounterState$optimistic(
  value: PnCounterState$,
): $pn_counter.PNCounter$;
export function PnCounterState$PnCounterState$3(value: PnCounterState$): _.List<
  PendingDelta$
>;
export function PnCounterState$PnCounterState$pending(value: PnCounterState$): _.List<
  PendingDelta$
>;
export function PnCounterState$PnCounterState$4(value: PnCounterState$): number;
export function PnCounterState$PnCounterState$next_pending_message_id(value: PnCounterState$): number;

export type PnCounterState$ = PnCounterState;

export class PendingDelta extends _.CustomType {
  /** @deprecated */
  constructor(delta: $pn_counter.PNCounter$, amount: number, message_id: number);
  /** @deprecated */
  delta: $pn_counter.PNCounter$;
  /** @deprecated */
  amount: number;
  /** @deprecated */
  message_id: number;
}
export function PendingDelta$PendingDelta(
  delta: $pn_counter.PNCounter$,
  amount: number,
  message_id: number,
): PendingDelta$;
export function PendingDelta$isPendingDelta(value: any): value is PendingDelta$;
export function PendingDelta$PendingDelta$0(value: PendingDelta$): $pn_counter.PNCounter$;
export function PendingDelta$PendingDelta$delta(
  value: PendingDelta$,
): $pn_counter.PNCounter$;
export function PendingDelta$PendingDelta$1(value: PendingDelta$): number;
export function PendingDelta$PendingDelta$amount(value: PendingDelta$): number;
export function PendingDelta$PendingDelta$2(value: PendingDelta$): number;
export function PendingDelta$PendingDelta$message_id(value: PendingDelta$): number;

export type PendingDelta$ = PendingDelta;

export class Update extends _.CustomType {
  /** @deprecated */
  constructor(amount: number, delta: $pn_counter.PNCounter$);
  /** @deprecated */
  amount: number;
  /** @deprecated */
  delta: $pn_counter.PNCounter$;
}
export function PnCounterOperation$Update(
  amount: number,
  delta: $pn_counter.PNCounter$,
): PnCounterOperation$;
export function PnCounterOperation$isUpdate(
  value: any,
): value is PnCounterOperation$;
export function PnCounterOperation$Update$0(value: PnCounterOperation$): number;
export function PnCounterOperation$Update$amount(value: PnCounterOperation$): number;
export function PnCounterOperation$Update$1(
  value: PnCounterOperation$,
): $pn_counter.PNCounter$;
export function PnCounterOperation$Update$delta(value: PnCounterOperation$): $pn_counter.PNCounter$;

export type PnCounterOperation$ = Update;

export class Updated extends _.CustomType {
  /** @deprecated */
  constructor(applied: number, new_value: number);
  /** @deprecated */
  applied: number;
  /** @deprecated */
  new_value: number;
}
export function PnCounterEvent$Updated(
  applied: number,
  new_value: number,
): PnCounterEvent$;
export function PnCounterEvent$isUpdated(value: any): value is PnCounterEvent$;
export function PnCounterEvent$Updated$0(value: PnCounterEvent$): number;
export function PnCounterEvent$Updated$applied(value: PnCounterEvent$): number;
export function PnCounterEvent$Updated$1(value: PnCounterEvent$): number;
export function PnCounterEvent$Updated$new_value(value: PnCounterEvent$): number;

export type PnCounterEvent$ = Updated;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(operation: PnCounterOperation$, detail: string);
  /** @deprecated */
  operation: PnCounterOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(
  operation: PnCounterOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): PnCounterOperation$;
export function KernelError$UnexpectedAck$operation(
  value: KernelError$,
): PnCounterOperation$;
export function KernelError$UnexpectedAck$1(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(operation: PnCounterOperation$, detail: string);
  /** @deprecated */
  operation: PnCounterOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(
  operation: PnCounterOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): PnCounterOperation$;
export function KernelError$UnexpectedRollback$operation(
  value: KernelError$,
): PnCounterOperation$;
export function KernelError$UnexpectedRollback$1(value: KernelError$): string;
export function KernelError$UnexpectedRollback$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAck | UnexpectedRollback;

export function KernelError$detail(value: KernelError$): string;
export function KernelError$operation(value: KernelError$): PnCounterOperation$;

export function new$(replica_id: $replica_id.ReplicaId$): PnCounterState$;

export function value(state: PnCounterState$): number;

export function sequenced_value(state: PnCounterState$): number;

export function update(state: PnCounterState$, amount: number): [
  PnCounterState$,
  _.List<PnCounterEvent$>,
  PnCounterOperation$,
  number
];

export function p2p_update(state: PnCounterState$, amount: number): [
  PnCounterState$,
  _.List<PnCounterEvent$>,
  PnCounterOperation$
];

export function p2p_merge(state: PnCounterState$, other: $pn_counter.PNCounter$): [
  PnCounterState$,
  _.List<PnCounterEvent$>
];

export function apply_remote(
  state: PnCounterState$,
  operation: PnCounterOperation$
): [PnCounterState$, _.List<PnCounterEvent$>];

export function ack_local(
  state: PnCounterState$,
  operation: PnCounterOperation$
): _.Result<PnCounterState$, KernelError$>;

export function ack_local_with_message_id(
  state: PnCounterState$,
  operation: PnCounterOperation$,
  message_id: number
): _.Result<PnCounterState$, KernelError$>;

export function rollback(
  state: PnCounterState$,
  operation: PnCounterOperation$,
  message_id: number
): _.Result<[PnCounterState$, _.List<PnCounterEvent$>], KernelError$>;

export function apply_stashed_operation(
  state: PnCounterState$,
  operation: PnCounterOperation$
): [PnCounterState$, _.List<PnCounterEvent$>, PnCounterOperation$, number];

export function summary(state: PnCounterState$): $json.Json$;

export function from_summary(
  summary_json: string,
  replica_id: $replica_id.ReplicaId$
): _.Result<PnCounterState$, $json.DecodeError$>;

export function from_sequenced(
  state: $pn_counter.PNCounter$,
  replica_id: $replica_id.ReplicaId$
): PnCounterState$;

export function check_cache_coherence(state: PnCounterState$): _.Result<
  undefined,
  string
>;
