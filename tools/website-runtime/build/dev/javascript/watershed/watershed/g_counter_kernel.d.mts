import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $g_counter from "../../lattice_counters/lattice_counters/g_counter.d.mts";
import type * as _ from "../gleam.d.mts";

export class GCounterState extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    sequenced: $g_counter.GCounter$,
    optimistic: $g_counter.GCounter$,
    pending: _.List<PendingDelta$>,
    next_pending_message_id: number
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  sequenced: $g_counter.GCounter$;
  /** @deprecated */
  optimistic: $g_counter.GCounter$;
  /** @deprecated */
  pending: _.List<PendingDelta$>;
  /** @deprecated */
  next_pending_message_id: number;
}
export function GCounterState$GCounterState(
  replica_id: $replica_id.ReplicaId$,
  sequenced: $g_counter.GCounter$,
  optimistic: $g_counter.GCounter$,
  pending: _.List<PendingDelta$>,
  next_pending_message_id: number,
): GCounterState$;
export function GCounterState$isGCounterState(
  value: any,
): value is GCounterState$;
export function GCounterState$GCounterState$0(value: GCounterState$): $replica_id.ReplicaId$;
export function GCounterState$GCounterState$replica_id(
  value: GCounterState$,
): $replica_id.ReplicaId$;
export function GCounterState$GCounterState$1(value: GCounterState$): $g_counter.GCounter$;
export function GCounterState$GCounterState$sequenced(
  value: GCounterState$,
): $g_counter.GCounter$;
export function GCounterState$GCounterState$2(value: GCounterState$): $g_counter.GCounter$;
export function GCounterState$GCounterState$optimistic(
  value: GCounterState$,
): $g_counter.GCounter$;
export function GCounterState$GCounterState$3(value: GCounterState$): _.List<
  PendingDelta$
>;
export function GCounterState$GCounterState$pending(value: GCounterState$): _.List<
  PendingDelta$
>;
export function GCounterState$GCounterState$4(value: GCounterState$): number;
export function GCounterState$GCounterState$next_pending_message_id(value: GCounterState$): number;

export type GCounterState$ = GCounterState;

export class PendingDelta extends _.CustomType {
  /** @deprecated */
  constructor(delta: $g_counter.GCounter$, amount: number, message_id: number);
  /** @deprecated */
  delta: $g_counter.GCounter$;
  /** @deprecated */
  amount: number;
  /** @deprecated */
  message_id: number;
}
export function PendingDelta$PendingDelta(
  delta: $g_counter.GCounter$,
  amount: number,
  message_id: number,
): PendingDelta$;
export function PendingDelta$isPendingDelta(value: any): value is PendingDelta$;
export function PendingDelta$PendingDelta$0(value: PendingDelta$): $g_counter.GCounter$;
export function PendingDelta$PendingDelta$delta(
  value: PendingDelta$,
): $g_counter.GCounter$;
export function PendingDelta$PendingDelta$1(value: PendingDelta$): number;
export function PendingDelta$PendingDelta$amount(value: PendingDelta$): number;
export function PendingDelta$PendingDelta$2(value: PendingDelta$): number;
export function PendingDelta$PendingDelta$message_id(value: PendingDelta$): number;

export type PendingDelta$ = PendingDelta;

export class Increment extends _.CustomType {
  /** @deprecated */
  constructor(amount: number, delta: $g_counter.GCounter$);
  /** @deprecated */
  amount: number;
  /** @deprecated */
  delta: $g_counter.GCounter$;
}
export function GCounterOperation$Increment(
  amount: number,
  delta: $g_counter.GCounter$,
): GCounterOperation$;
export function GCounterOperation$isIncrement(
  value: any,
): value is GCounterOperation$;
export function GCounterOperation$Increment$0(value: GCounterOperation$): number;
export function GCounterOperation$Increment$amount(
  value: GCounterOperation$,
): number;
export function GCounterOperation$Increment$1(value: GCounterOperation$): $g_counter.GCounter$;
export function GCounterOperation$Increment$delta(
  value: GCounterOperation$,
): $g_counter.GCounter$;

export type GCounterOperation$ = Increment;

export class Updated extends _.CustomType {
  /** @deprecated */
  constructor(applied: number, new_value: number);
  /** @deprecated */
  applied: number;
  /** @deprecated */
  new_value: number;
}
export function GCounterEvent$Updated(
  applied: number,
  new_value: number,
): GCounterEvent$;
export function GCounterEvent$isUpdated(value: any): value is GCounterEvent$;
export function GCounterEvent$Updated$0(value: GCounterEvent$): number;
export function GCounterEvent$Updated$applied(value: GCounterEvent$): number;
export function GCounterEvent$Updated$1(value: GCounterEvent$): number;
export function GCounterEvent$Updated$new_value(value: GCounterEvent$): number;

export type GCounterEvent$ = Updated;

export class NegativeIncrement extends _.CustomType {
  /** @deprecated */
  constructor(amount: number);
  /** @deprecated */
  amount: number;
}
export function EditError$NegativeIncrement(amount: number): EditError$;
export function EditError$isNegativeIncrement(value: any): value is EditError$;
export function EditError$NegativeIncrement$0(value: EditError$): number;
export function EditError$NegativeIncrement$amount(value: EditError$): number;

export type EditError$ = NegativeIncrement;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(operation: GCounterOperation$, detail: string);
  /** @deprecated */
  operation: GCounterOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(
  operation: GCounterOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): GCounterOperation$;
export function KernelError$UnexpectedAck$operation(
  value: KernelError$,
): GCounterOperation$;
export function KernelError$UnexpectedAck$1(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(operation: GCounterOperation$, detail: string);
  /** @deprecated */
  operation: GCounterOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(
  operation: GCounterOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): GCounterOperation$;
export function KernelError$UnexpectedRollback$operation(
  value: KernelError$,
): GCounterOperation$;
export function KernelError$UnexpectedRollback$1(value: KernelError$): string;
export function KernelError$UnexpectedRollback$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAck | UnexpectedRollback;

export function KernelError$detail(value: KernelError$): string;
export function KernelError$operation(value: KernelError$): GCounterOperation$;

export function edit_error_text(error: EditError$): string;

export function new$(replica_id: $replica_id.ReplicaId$): GCounterState$;

export function value(state: GCounterState$): number;

export function sequenced_value(state: GCounterState$): number;

export function increment(state: GCounterState$, amount: number): _.Result<
  [GCounterState$, _.List<GCounterEvent$>, GCounterOperation$, number],
  EditError$
>;

export function p2p_increment(state: GCounterState$, amount: number): _.Result<
  [GCounterState$, _.List<GCounterEvent$>, GCounterOperation$],
  EditError$
>;

export function p2p_merge(state: GCounterState$, other: $g_counter.GCounter$): [
  GCounterState$,
  _.List<GCounterEvent$>
];

export function apply_remote(
  state: GCounterState$,
  operation: GCounterOperation$
): [GCounterState$, _.List<GCounterEvent$>];

export function ack_local(state: GCounterState$, operation: GCounterOperation$): _.Result<
  GCounterState$,
  KernelError$
>;

export function ack_local_with_message_id(
  state: GCounterState$,
  operation: GCounterOperation$,
  message_id: number
): _.Result<GCounterState$, KernelError$>;

export function rollback(
  state: GCounterState$,
  operation: GCounterOperation$,
  message_id: number
): _.Result<[GCounterState$, _.List<GCounterEvent$>], KernelError$>;

export function apply_stashed_operation(
  state: GCounterState$,
  operation: GCounterOperation$
): [GCounterState$, _.List<GCounterEvent$>, GCounterOperation$, number];

export function summary(state: GCounterState$): $json.Json$;

export function from_sequenced(
  state: $g_counter.GCounter$,
  replica_id: $replica_id.ReplicaId$
): GCounterState$;

export function from_summary(
  summary_json: string,
  replica_id: $replica_id.ReplicaId$
): _.Result<GCounterState$, $json.DecodeError$>;

export function check_cache_coherence(state: GCounterState$): _.Result<
  undefined,
  string
>;
