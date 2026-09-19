import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $crdt from "../../lattice_maps/lattice_maps/crdt.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $lww_clock from "../watershed/lww_clock.d.mts";

export class LwwMapState extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    sequenced: $crdt.LWWMap$<string>,
    optimistic: $crdt.LWWMap$<string>,
    pending: _.List<PendingOp$>,
    next_pending_message_id: number,
    last_seen: $dict.Dict$<string, number>
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  sequenced: $crdt.LWWMap$<string>;
  /** @deprecated */
  optimistic: $crdt.LWWMap$<string>;
  /** @deprecated */
  pending: _.List<PendingOp$>;
  /** @deprecated */
  next_pending_message_id: number;
  /** @deprecated */
  last_seen: $dict.Dict$<string, number>;
}
export function LwwMapState$LwwMapState(
  replica_id: $replica_id.ReplicaId$,
  sequenced: $crdt.LWWMap$<string>,
  optimistic: $crdt.LWWMap$<string>,
  pending: _.List<PendingOp$>,
  next_pending_message_id: number,
  last_seen: $dict.Dict$<string, number>,
): LwwMapState$;
export function LwwMapState$isLwwMapState(value: any): value is LwwMapState$;
export function LwwMapState$LwwMapState$0(value: LwwMapState$): $replica_id.ReplicaId$;
export function LwwMapState$LwwMapState$replica_id(
  value: LwwMapState$,
): $replica_id.ReplicaId$;
export function LwwMapState$LwwMapState$1(value: LwwMapState$): $crdt.LWWMap$<
  string
>;
export function LwwMapState$LwwMapState$sequenced(value: LwwMapState$): $crdt.LWWMap$<
  string
>;
export function LwwMapState$LwwMapState$2(value: LwwMapState$): $crdt.LWWMap$<
  string
>;
export function LwwMapState$LwwMapState$optimistic(value: LwwMapState$): $crdt.LWWMap$<
  string
>;
export function LwwMapState$LwwMapState$3(value: LwwMapState$): _.List<
  PendingOp$
>;
export function LwwMapState$LwwMapState$pending(value: LwwMapState$): _.List<
  PendingOp$
>;
export function LwwMapState$LwwMapState$4(value: LwwMapState$): number;
export function LwwMapState$LwwMapState$next_pending_message_id(value: LwwMapState$): number;
export function LwwMapState$LwwMapState$5(
  value: LwwMapState$,
): $dict.Dict$<string, number>;
export function LwwMapState$LwwMapState$last_seen(value: LwwMapState$): $dict.Dict$<
  string,
  number
>;

export type LwwMapState$ = LwwMapState;

export class PendingOp extends _.CustomType {
  /** @deprecated */
  constructor(operation: LwwMapOperation$, message_id: number);
  /** @deprecated */
  operation: LwwMapOperation$;
  /** @deprecated */
  message_id: number;
}
export function PendingOp$PendingOp(
  operation: LwwMapOperation$,
  message_id: number,
): PendingOp$;
export function PendingOp$isPendingOp(value: any): value is PendingOp$;
export function PendingOp$PendingOp$0(value: PendingOp$): LwwMapOperation$;
export function PendingOp$PendingOp$operation(value: PendingOp$): LwwMapOperation$;
export function PendingOp$PendingOp$1(
  value: PendingOp$,
): number;
export function PendingOp$PendingOp$message_id(value: PendingOp$): number;

export type PendingOp$ = PendingOp;

export class Set extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    value: string,
    timestamp: number,
    delta: $crdt.LWWMap$<string>
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: string;
  /** @deprecated */
  timestamp: number;
  /** @deprecated */
  delta: $crdt.LWWMap$<string>;
}
export function LwwMapOperation$Set(
  key: string,
  value: string,
  timestamp: number,
  delta: $crdt.LWWMap$<string>,
): LwwMapOperation$;
export function LwwMapOperation$isSet(value: any): value is LwwMapOperation$;
export function LwwMapOperation$Set$0(value: LwwMapOperation$): string;
export function LwwMapOperation$Set$key(value: LwwMapOperation$): string;
export function LwwMapOperation$Set$1(value: LwwMapOperation$): string;
export function LwwMapOperation$Set$value(value: LwwMapOperation$): string;
export function LwwMapOperation$Set$2(value: LwwMapOperation$): number;
export function LwwMapOperation$Set$timestamp(value: LwwMapOperation$): number;
export function LwwMapOperation$Set$3(value: LwwMapOperation$): $crdt.LWWMap$<
  string
>;
export function LwwMapOperation$Set$delta(value: LwwMapOperation$): $crdt.LWWMap$<
  string
>;

export class Remove extends _.CustomType {
  /** @deprecated */
  constructor(key: string, timestamp: number, delta: $crdt.LWWMap$<string>);
  /** @deprecated */
  key: string;
  /** @deprecated */
  timestamp: number;
  /** @deprecated */
  delta: $crdt.LWWMap$<string>;
}
export function LwwMapOperation$Remove(
  key: string,
  timestamp: number,
  delta: $crdt.LWWMap$<string>,
): LwwMapOperation$;
export function LwwMapOperation$isRemove(value: any): value is LwwMapOperation$;
export function LwwMapOperation$Remove$0(value: LwwMapOperation$): string;
export function LwwMapOperation$Remove$key(value: LwwMapOperation$): string;
export function LwwMapOperation$Remove$1(value: LwwMapOperation$): number;
export function LwwMapOperation$Remove$timestamp(value: LwwMapOperation$): number;
export function LwwMapOperation$Remove$2(
  value: LwwMapOperation$,
): $crdt.LWWMap$<string>;
export function LwwMapOperation$Remove$delta(value: LwwMapOperation$): $crdt.LWWMap$<
  string
>;

export type LwwMapOperation$ = Set | Remove;

export function LwwMapOperation$key(value: LwwMapOperation$): string;

export class ValueChanged extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    previous_value: $option.Option$<string>,
    value: $option.Option$<string>
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  previous_value: $option.Option$<string>;
  /** @deprecated */
  value: $option.Option$<string>;
}
export function LwwMapEvent$ValueChanged(
  key: string,
  previous_value: $option.Option$<string>,
  value: $option.Option$<string>,
): LwwMapEvent$;
export function LwwMapEvent$isValueChanged(value: any): value is LwwMapEvent$;
export function LwwMapEvent$ValueChanged$0(value: LwwMapEvent$): string;
export function LwwMapEvent$ValueChanged$key(value: LwwMapEvent$): string;
export function LwwMapEvent$ValueChanged$1(value: LwwMapEvent$): $option.Option$<
  string
>;
export function LwwMapEvent$ValueChanged$previous_value(value: LwwMapEvent$): $option.Option$<
  string
>;
export function LwwMapEvent$ValueChanged$2(value: LwwMapEvent$): $option.Option$<
  string
>;
export function LwwMapEvent$ValueChanged$value(value: LwwMapEvent$): $option.Option$<
  string
>;

export type LwwMapEvent$ = ValueChanged;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(operation: LwwMapOperation$, detail: string);
  /** @deprecated */
  operation: LwwMapOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(
  operation: LwwMapOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): LwwMapOperation$;
export function KernelError$UnexpectedAck$operation(
  value: KernelError$,
): LwwMapOperation$;
export function KernelError$UnexpectedAck$1(value: KernelError$): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export class UnexpectedRollback extends _.CustomType {
  /** @deprecated */
  constructor(operation: LwwMapOperation$, detail: string);
  /** @deprecated */
  operation: LwwMapOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedRollback(
  operation: LwwMapOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedRollback(
  value: any,
): value is KernelError$;
export function KernelError$UnexpectedRollback$0(value: KernelError$): LwwMapOperation$;
export function KernelError$UnexpectedRollback$operation(
  value: KernelError$,
): LwwMapOperation$;
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

export class UnsupportedPruning extends _.CustomType {
  /** @deprecated */
  constructor(timestamp: number);
  /** @deprecated */
  timestamp: number;
}
export function KernelError$UnsupportedPruning(timestamp: number): KernelError$;
export function KernelError$isUnsupportedPruning(
  value: any,
): value is KernelError$;
export function KernelError$UnsupportedPruning$0(value: KernelError$): number;
export function KernelError$UnsupportedPruning$timestamp(value: KernelError$): number;

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

export type KernelError$ = UnexpectedAck | UnexpectedRollback | Clock | InvalidState | UnsupportedPruning | DecodeError;

export type LWWMap = $crdt.LWWMap$<string>;

export function new$(replica_id: $replica_id.ReplicaId$): LwwMapState$;

export function get(state: LwwMapState$, key: string): _.Result<
  string,
  undefined
>;

export function entries(state: LwwMapState$): _.List<[string, string]>;

export function sequenced_entries(state: LwwMapState$): _.List<[string, string]>;

export function keys(state: LwwMapState$): _.List<string>;

export function decoder(): $decode.Decoder$<$crdt.LWWMap$<string>>;

export function validate_operation(operation: LwwMapOperation$): _.Result<
  undefined,
  KernelError$
>;

export function apply_stashed_operation(
  state: LwwMapState$,
  operation: LwwMapOperation$
): _.Result<
  [LwwMapState$, _.List<LwwMapEvent$>, LwwMapOperation$, number],
  KernelError$
>;

export function set(
  state: LwwMapState$,
  key: string,
  value: string,
  wall_clock: number
): _.Result<
  [LwwMapState$, _.List<LwwMapEvent$>, LwwMapOperation$, number],
  KernelError$
>;

export function remove(state: LwwMapState$, key: string, wall_clock: number): _.Result<
  [LwwMapState$, _.List<LwwMapEvent$>, LwwMapOperation$, number],
  KernelError$
>;

export function p2p_merge(state: LwwMapState$, other: $crdt.LWWMap$<string>): _.Result<
  [LwwMapState$, _.List<LwwMapEvent$>],
  KernelError$
>;

export function p2p_set(
  state: LwwMapState$,
  key: string,
  value: string,
  wall_clock: number
): _.Result<
  [LwwMapState$, _.List<LwwMapEvent$>, LwwMapOperation$],
  KernelError$
>;

export function p2p_remove(state: LwwMapState$, key: string, wall_clock: number): _.Result<
  [LwwMapState$, _.List<LwwMapEvent$>, LwwMapOperation$],
  KernelError$
>;

export function apply_remote(state: LwwMapState$, operation: LwwMapOperation$): _.Result<
  [LwwMapState$, _.List<LwwMapEvent$>],
  KernelError$
>;

export function ack_local(state: LwwMapState$, operation: LwwMapOperation$): _.Result<
  LwwMapState$,
  KernelError$
>;

export function ack_local_with_message_id(
  state: LwwMapState$,
  operation: LwwMapOperation$,
  message_id: number
): _.Result<LwwMapState$, KernelError$>;

export function rollback(
  state: LwwMapState$,
  operation: LwwMapOperation$,
  message_id: number
): _.Result<[LwwMapState$, _.List<LwwMapEvent$>], KernelError$>;

export function promote_attach(state: LwwMapState$): LwwMapState$;

export function summary(state: LwwMapState$): $json.Json$;

export function from_sequenced(
  map: $crdt.LWWMap$<string>,
  replica_id: $replica_id.ReplicaId$
): _.Result<LwwMapState$, KernelError$>;

export function from_summary(source: string, replica_id: $replica_id.ReplicaId$): _.Result<
  LwwMapState$,
  KernelError$
>;

export function check_cache_coherence(state: LwwMapState$): _.Result<
  undefined,
  string
>;
