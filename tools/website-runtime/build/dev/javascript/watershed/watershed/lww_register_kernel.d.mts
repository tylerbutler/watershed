import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $lww_register from "../../lattice_registers/lattice_registers/lww_register.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $lww_clock from "../watershed/lww_clock.d.mts";

export class LwwRegisterState extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    sequenced: $lww_register.LWWRegister$<string>,
    optimistic: $lww_register.LWWRegister$<string>,
    pending: _.List<PendingOp$>,
    next_pending_message_id: number,
    last_seen: number
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  sequenced: $lww_register.LWWRegister$<string>;
  /** @deprecated */
  optimistic: $lww_register.LWWRegister$<string>;
  /** @deprecated */
  pending: _.List<PendingOp$>;
  /** @deprecated */
  next_pending_message_id: number;
  /** @deprecated */
  last_seen: number;
}
export function LwwRegisterState$LwwRegisterState(
  replica_id: $replica_id.ReplicaId$,
  sequenced: $lww_register.LWWRegister$<string>,
  optimistic: $lww_register.LWWRegister$<string>,
  pending: _.List<PendingOp$>,
  next_pending_message_id: number,
  last_seen: number,
): LwwRegisterState$;
export function LwwRegisterState$isLwwRegisterState(
  value: any,
): value is LwwRegisterState$;
export function LwwRegisterState$LwwRegisterState$0(value: LwwRegisterState$): $replica_id.ReplicaId$;
export function LwwRegisterState$LwwRegisterState$replica_id(
  value: LwwRegisterState$,
): $replica_id.ReplicaId$;
export function LwwRegisterState$LwwRegisterState$1(value: LwwRegisterState$): $lww_register.LWWRegister$<
  string
>;
export function LwwRegisterState$LwwRegisterState$sequenced(value: LwwRegisterState$): $lww_register.LWWRegister$<
  string
>;
export function LwwRegisterState$LwwRegisterState$2(value: LwwRegisterState$): $lww_register.LWWRegister$<
  string
>;
export function LwwRegisterState$LwwRegisterState$optimistic(value: LwwRegisterState$): $lww_register.LWWRegister$<
  string
>;
export function LwwRegisterState$LwwRegisterState$3(value: LwwRegisterState$): _.List<
  PendingOp$
>;
export function LwwRegisterState$LwwRegisterState$pending(value: LwwRegisterState$): _.List<
  PendingOp$
>;
export function LwwRegisterState$LwwRegisterState$4(value: LwwRegisterState$): number;
export function LwwRegisterState$LwwRegisterState$next_pending_message_id(
  value: LwwRegisterState$,
): number;
export function LwwRegisterState$LwwRegisterState$5(value: LwwRegisterState$): number;
export function LwwRegisterState$LwwRegisterState$last_seen(
  value: LwwRegisterState$,
): number;

export type LwwRegisterState$ = LwwRegisterState;

export class PendingOp extends _.CustomType {
  /** @deprecated */
  constructor(operation: LwwRegisterOperation$, message_id: number);
  /** @deprecated */
  operation: LwwRegisterOperation$;
  /** @deprecated */
  message_id: number;
}
export function PendingOp$PendingOp(
  operation: LwwRegisterOperation$,
  message_id: number,
): PendingOp$;
export function PendingOp$isPendingOp(value: any): value is PendingOp$;
export function PendingOp$PendingOp$0(value: PendingOp$): LwwRegisterOperation$;
export function PendingOp$PendingOp$operation(value: PendingOp$): LwwRegisterOperation$;
export function PendingOp$PendingOp$1(
  value: PendingOp$,
): number;
export function PendingOp$PendingOp$message_id(value: PendingOp$): number;

export type PendingOp$ = PendingOp;

export class Set extends _.CustomType {
  /** @deprecated */
  constructor(
    value: string,
    timestamp: number,
    delta: $lww_register.LWWRegister$<string>
  );
  /** @deprecated */
  value: string;
  /** @deprecated */
  timestamp: number;
  /** @deprecated */
  delta: $lww_register.LWWRegister$<string>;
}
export function LwwRegisterOperation$Set(
  value: string,
  timestamp: number,
  delta: $lww_register.LWWRegister$<string>,
): LwwRegisterOperation$;
export function LwwRegisterOperation$isSet(
  value: any,
): value is LwwRegisterOperation$;
export function LwwRegisterOperation$Set$0(value: LwwRegisterOperation$): string;
export function LwwRegisterOperation$Set$value(
  value: LwwRegisterOperation$,
): string;
export function LwwRegisterOperation$Set$1(value: LwwRegisterOperation$): number;
export function LwwRegisterOperation$Set$timestamp(
  value: LwwRegisterOperation$,
): number;
export function LwwRegisterOperation$Set$2(value: LwwRegisterOperation$): $lww_register.LWWRegister$<
  string
>;
export function LwwRegisterOperation$Set$delta(value: LwwRegisterOperation$): $lww_register.LWWRegister$<
  string
>;

export type LwwRegisterOperation$ = Set;

export class Changed extends _.CustomType {
  /** @deprecated */
  constructor(previous_value: string, value: string);
  /** @deprecated */
  previous_value: string;
  /** @deprecated */
  value: string;
}
export function LwwRegisterEvent$Changed(
  previous_value: string,
  value: string,
): LwwRegisterEvent$;
export function LwwRegisterEvent$isChanged(
  value: any,
): value is LwwRegisterEvent$;
export function LwwRegisterEvent$Changed$0(value: LwwRegisterEvent$): string;
export function LwwRegisterEvent$Changed$previous_value(value: LwwRegisterEvent$): string;
export function LwwRegisterEvent$Changed$1(
  value: LwwRegisterEvent$,
): string;
export function LwwRegisterEvent$Changed$value(value: LwwRegisterEvent$): string;

export type LwwRegisterEvent$ = Changed;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(operation: LwwRegisterOperation$, detail: string);
  /** @deprecated */
  operation: LwwRegisterOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(
  operation: LwwRegisterOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): LwwRegisterOperation$;
export function KernelError$UnexpectedAck$operation(
  value: KernelError$,
): LwwRegisterOperation$;
export function KernelError$UnexpectedAck$1(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(operation: LwwRegisterOperation$, detail: string);
  /** @deprecated */
  operation: LwwRegisterOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(
  operation: LwwRegisterOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): LwwRegisterOperation$;
export function KernelError$UnexpectedRollback$operation(
  value: KernelError$,
): LwwRegisterOperation$;
export function KernelError$UnexpectedRollback$1(value: KernelError$): string;
export function KernelError$UnexpectedRollback$detail(value: KernelError$): string;

export class Clock extends _.CustomType {
  /** @deprecated */
  constructor(error: $lww_clock.ClockError$);
  /** @deprecated */
  error: $lww_clock.ClockError$;
}
export function KernelError$Clock(error: $lww_clock.ClockError$): KernelError$;
export function KernelError$isClock(value: any): value is KernelError$;
export function KernelError$Clock$0(value: KernelError$): $lww_clock.ClockError$;
export function KernelError$Clock$error(
  value: KernelError$,
): $lww_clock.ClockError$;

export class InvalidState extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$InvalidState(detail: string): KernelError$;
export function KernelError$isInvalidState(value: any): value is KernelError$;
export function KernelError$InvalidState$0(value: KernelError$): string;
export function KernelError$InvalidState$detail(value: KernelError$): string;

export class DecodeError extends _.CustomType {
  /** @deprecated */
  constructor(error: $json.DecodeError$);
  /** @deprecated */
  error: $json.DecodeError$;
}
export function KernelError$DecodeError(
  error: $json.DecodeError$,
): KernelError$;
export function KernelError$isDecodeError(value: any): value is KernelError$;
export function KernelError$DecodeError$0(value: KernelError$): $json.DecodeError$;
export function KernelError$DecodeError$error(
  value: KernelError$,
): $json.DecodeError$;

export type KernelError$ = UnexpectedAck | UnexpectedRollback | Clock | InvalidState | DecodeError;

export function new$(replica_id: $replica_id.ReplicaId$): LwwRegisterState$;

export function value(state: LwwRegisterState$): string;

export function sequenced_value(state: LwwRegisterState$): string;

export function apply_stashed_operation(
  state: LwwRegisterState$,
  operation: LwwRegisterOperation$
): _.Result<
  [LwwRegisterState$, _.List<LwwRegisterEvent$>, LwwRegisterOperation$, number],
  KernelError$
>;

export function set(
  state: LwwRegisterState$,
  next_value: string,
  wall_clock: number
): _.Result<
  [LwwRegisterState$, _.List<LwwRegisterEvent$>, LwwRegisterOperation$, number],
  KernelError$
>;

export function p2p_set(
  state: LwwRegisterState$,
  next_value: string,
  wall_clock: number
): _.Result<
  [LwwRegisterState$, _.List<LwwRegisterEvent$>, LwwRegisterOperation$],
  KernelError$
>;

export function apply_remote(
  state: LwwRegisterState$,
  operation: LwwRegisterOperation$
): _.Result<[LwwRegisterState$, _.List<LwwRegisterEvent$>], KernelError$>;

export function p2p_merge(
  state: LwwRegisterState$,
  other: $lww_register.LWWRegister$<string>
): _.Result<[LwwRegisterState$, _.List<LwwRegisterEvent$>], KernelError$>;

export function ack_local(
  state: LwwRegisterState$,
  operation: LwwRegisterOperation$
): _.Result<LwwRegisterState$, KernelError$>;

export function ack_local_with_message_id(
  state: LwwRegisterState$,
  operation: LwwRegisterOperation$,
  message_id: number
): _.Result<LwwRegisterState$, KernelError$>;

export function rollback(
  state: LwwRegisterState$,
  operation: LwwRegisterOperation$,
  message_id: number
): _.Result<[LwwRegisterState$, _.List<LwwRegisterEvent$>], KernelError$>;

export function summary(state: LwwRegisterState$): $json.Json$;

export function from_sequenced(
  register: $lww_register.LWWRegister$<string>,
  replica_id: $replica_id.ReplicaId$
): _.Result<LwwRegisterState$, KernelError$>;

export function from_summary(source: string, replica_id: $replica_id.ReplicaId$): _.Result<
  LwwRegisterState$,
  KernelError$
>;

export function check_cache_coherence(state: LwwRegisterState$): _.Result<
  undefined,
  string
>;

export function pending_timestamp(operation: LwwRegisterOperation$): number;
