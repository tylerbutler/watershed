import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $mv_register from "../../lattice_registers/lattice_registers/mv_register.d.mts";
import type * as _ from "../gleam.d.mts";

export class MvRegisterState extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    sequenced: $mv_register.MVRegister$<string>,
    optimistic: $mv_register.MVRegister$<string>,
    pending: _.List<PendingOp$>,
    next_pending_message_id: number,
    authored: $mv_register.MVRegister$<string>
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  sequenced: $mv_register.MVRegister$<string>;
  /** @deprecated */
  optimistic: $mv_register.MVRegister$<string>;
  /** @deprecated */
  pending: _.List<PendingOp$>;
  /** @deprecated */
  next_pending_message_id: number;
  /** @deprecated */
  authored: $mv_register.MVRegister$<string>;
}
export function MvRegisterState$MvRegisterState(
  replica_id: $replica_id.ReplicaId$,
  sequenced: $mv_register.MVRegister$<string>,
  optimistic: $mv_register.MVRegister$<string>,
  pending: _.List<PendingOp$>,
  next_pending_message_id: number,
  authored: $mv_register.MVRegister$<string>,
): MvRegisterState$;
export function MvRegisterState$isMvRegisterState(
  value: any,
): value is MvRegisterState$;
export function MvRegisterState$MvRegisterState$0(value: MvRegisterState$): $replica_id.ReplicaId$;
export function MvRegisterState$MvRegisterState$replica_id(
  value: MvRegisterState$,
): $replica_id.ReplicaId$;
export function MvRegisterState$MvRegisterState$1(value: MvRegisterState$): $mv_register.MVRegister$<
  string
>;
export function MvRegisterState$MvRegisterState$sequenced(value: MvRegisterState$): $mv_register.MVRegister$<
  string
>;
export function MvRegisterState$MvRegisterState$2(value: MvRegisterState$): $mv_register.MVRegister$<
  string
>;
export function MvRegisterState$MvRegisterState$optimistic(value: MvRegisterState$): $mv_register.MVRegister$<
  string
>;
export function MvRegisterState$MvRegisterState$3(value: MvRegisterState$): _.List<
  PendingOp$
>;
export function MvRegisterState$MvRegisterState$pending(value: MvRegisterState$): _.List<
  PendingOp$
>;
export function MvRegisterState$MvRegisterState$4(value: MvRegisterState$): number;
export function MvRegisterState$MvRegisterState$next_pending_message_id(
  value: MvRegisterState$,
): number;
export function MvRegisterState$MvRegisterState$5(value: MvRegisterState$): $mv_register.MVRegister$<
  string
>;
export function MvRegisterState$MvRegisterState$authored(value: MvRegisterState$): $mv_register.MVRegister$<
  string
>;

export type MvRegisterState$ = MvRegisterState;

export class PendingOp extends _.CustomType {
  /** @deprecated */
  constructor(operation: MvRegisterOperation$, message_id: number);
  /** @deprecated */
  operation: MvRegisterOperation$;
  /** @deprecated */
  message_id: number;
}
export function PendingOp$PendingOp(
  operation: MvRegisterOperation$,
  message_id: number,
): PendingOp$;
export function PendingOp$isPendingOp(value: any): value is PendingOp$;
export function PendingOp$PendingOp$0(value: PendingOp$): MvRegisterOperation$;
export function PendingOp$PendingOp$operation(value: PendingOp$): MvRegisterOperation$;
export function PendingOp$PendingOp$1(
  value: PendingOp$,
): number;
export function PendingOp$PendingOp$message_id(value: PendingOp$): number;

export type PendingOp$ = PendingOp;

export class Set extends _.CustomType {
  /** @deprecated */
  constructor(value: string, delta: $mv_register.MVRegister$<string>);
  /** @deprecated */
  value: string;
  /** @deprecated */
  delta: $mv_register.MVRegister$<string>;
}
export function MvRegisterOperation$Set(
  value: string,
  delta: $mv_register.MVRegister$<string>,
): MvRegisterOperation$;
export function MvRegisterOperation$isSet(
  value: any,
): value is MvRegisterOperation$;
export function MvRegisterOperation$Set$0(value: MvRegisterOperation$): string;
export function MvRegisterOperation$Set$value(value: MvRegisterOperation$): string;
export function MvRegisterOperation$Set$1(
  value: MvRegisterOperation$,
): $mv_register.MVRegister$<string>;
export function MvRegisterOperation$Set$delta(value: MvRegisterOperation$): $mv_register.MVRegister$<
  string
>;

export type MvRegisterOperation$ = Set;

export class ValuesChanged extends _.CustomType {
  /** @deprecated */
  constructor(values: _.List<string>);
  /** @deprecated */
  values: _.List<string>;
}
export function MvRegisterEvent$ValuesChanged(
  values: _.List<string>,
): MvRegisterEvent$;
export function MvRegisterEvent$isValuesChanged(
  value: any,
): value is MvRegisterEvent$;
export function MvRegisterEvent$ValuesChanged$0(value: MvRegisterEvent$): _.List<
  string
>;
export function MvRegisterEvent$ValuesChanged$values(value: MvRegisterEvent$): _.List<
  string
>;

export type MvRegisterEvent$ = ValuesChanged;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(operation: MvRegisterOperation$, detail: string);
  /** @deprecated */
  operation: MvRegisterOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(
  operation: MvRegisterOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): MvRegisterOperation$;
export function KernelError$UnexpectedAck$operation(
  value: KernelError$,
): MvRegisterOperation$;
export function KernelError$UnexpectedAck$1(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(operation: MvRegisterOperation$, detail: string);
  /** @deprecated */
  operation: MvRegisterOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(
  operation: MvRegisterOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): MvRegisterOperation$;
export function KernelError$UnexpectedRollback$operation(
  value: KernelError$,
): MvRegisterOperation$;
export function KernelError$UnexpectedRollback$1(value: KernelError$): string;
export function KernelError$UnexpectedRollback$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAck | UnexpectedRollback;

export function KernelError$detail(value: KernelError$): string;
export function KernelError$operation(
  value: KernelError$,
): MvRegisterOperation$;

export function from_sequenced(
  register: $mv_register.MVRegister$<string>,
  replica_id: $replica_id.ReplicaId$
): MvRegisterState$;

export function new$(replica_id: $replica_id.ReplicaId$): MvRegisterState$;

export function values(state: MvRegisterState$): _.List<string>;

export function sequenced_values(state: MvRegisterState$): _.List<string>;

export function apply_stashed_operation(
  state: MvRegisterState$,
  operation: MvRegisterOperation$
): [MvRegisterState$, _.List<MvRegisterEvent$>, MvRegisterOperation$, number];

export function set(state: MvRegisterState$, value: string): [
  MvRegisterState$,
  _.List<MvRegisterEvent$>,
  MvRegisterOperation$,
  number
];

export function p2p_merge(
  state: MvRegisterState$,
  other: $mv_register.MVRegister$<string>
): [MvRegisterState$, _.List<MvRegisterEvent$>];

export function p2p_set(state: MvRegisterState$, value: string): [
  MvRegisterState$,
  _.List<MvRegisterEvent$>,
  MvRegisterOperation$
];

export function apply_remote(
  state: MvRegisterState$,
  operation: MvRegisterOperation$
): [MvRegisterState$, _.List<MvRegisterEvent$>];

export function ack_local(
  state: MvRegisterState$,
  operation: MvRegisterOperation$
): _.Result<MvRegisterState$, KernelError$>;

export function ack_local_with_message_id(
  state: MvRegisterState$,
  operation: MvRegisterOperation$,
  message_id: number
): _.Result<MvRegisterState$, KernelError$>;

export function rollback(
  state: MvRegisterState$,
  operation: MvRegisterOperation$,
  message_id: number
): _.Result<[MvRegisterState$, _.List<MvRegisterEvent$>], KernelError$>;

export function summary(state: MvRegisterState$): $json.Json$;

export function decode_crdt(source: string): _.Result<
  $mv_register.MVRegister$<string>,
  $json.DecodeError$
>;

export function from_summary(source: string, replica_id: $replica_id.ReplicaId$): _.Result<
  MvRegisterState$,
  $json.DecodeError$
>;

export function check_cache_coherence(state: MvRegisterState$): _.Result<
  undefined,
  string
>;
