import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $version_vector from "../../lattice_core/lattice_core/version_vector.d.mts";
import type * as $pn_counter from "../../lattice_counters/lattice_counters/pn_counter.d.mts";
import type * as $crdt from "../../lattice_maps/lattice_maps/crdt.d.mts";
import type * as $lww_register from "../../lattice_registers/lattice_registers/lww_register.d.mts";
import type * as $mv_register from "../../lattice_registers/lattice_registers/mv_register.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $or_map_set_leaf from "../watershed/or_map_set_leaf.d.mts";

export class TallyMode extends _.CustomType {}
export function OrMapMode$TallyMode(): OrMapMode$;
export function OrMapMode$isTallyMode(value: any): value is OrMapMode$;

export class RegisterMode extends _.CustomType {}
export function OrMapMode$RegisterMode(): OrMapMode$;
export function OrMapMode$isRegisterMode(value: any): value is OrMapMode$;

export class OrSetMode extends _.CustomType {}
export function OrMapMode$OrSetMode(): OrMapMode$;
export function OrMapMode$isOrSetMode(value: any): value is OrMapMode$;

export class MvRegisterMode extends _.CustomType {}
export function OrMapMode$MvRegisterMode(): OrMapMode$;
export function OrMapMode$isMvRegisterMode(value: any): value is OrMapMode$;

export type OrMapMode$ = TallyMode | RegisterMode | OrSetMode | MvRegisterMode;

export class Tally extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}
export function OrMapValue$Tally($0: number): OrMapValue$;
export function OrMapValue$isTally(value: any): value is OrMapValue$;
export function OrMapValue$Tally$0(value: OrMapValue$): number;

export class Register extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function OrMapValue$Register($0: string): OrMapValue$;
export function OrMapValue$isRegister(value: any): value is OrMapValue$;
export function OrMapValue$Register$0(value: OrMapValue$): string;

export class SetMembers extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<string>);
  /** @deprecated */
  0: _.List<string>;
}
export function OrMapValue$SetMembers($0: _.List<string>): OrMapValue$;
export function OrMapValue$isSetMembers(value: any): value is OrMapValue$;
export function OrMapValue$SetMembers$0(value: OrMapValue$): _.List<string>;

export class MvRegister extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<string>);
  /** @deprecated */
  0: _.List<string>;
}
export function OrMapValue$MvRegister($0: _.List<string>): OrMapValue$;
export function OrMapValue$isMvRegister(value: any): value is OrMapValue$;
export function OrMapValue$MvRegister$0(value: OrMapValue$): _.List<string>;

export type OrMapValue$ = Tally | Register | SetMembers | MvRegister;

export class OrMapState extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    mode: OrMapMode$,
    sequenced: $crdt.ORMap$<string>,
    optimistic: $crdt.ORMap$<string>,
    authored: $crdt.ORMap$<string>,
    own_tallies: $dict.Dict$<string, [number, number]>,
    authored_mv_registers: $dict.Dict$<string, $mv_register.MVRegister$<string>>,
    register_clock: $dict.Dict$<string, number>,
    set_clocks: $or_map_set_leaf.Clocks$,
    pending: _.List<PendingOperation$>,
    next_pending_message_id: number
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  mode: OrMapMode$;
  /** @deprecated */
  sequenced: $crdt.ORMap$<string>;
  /** @deprecated */
  optimistic: $crdt.ORMap$<string>;
  /** @deprecated */
  authored: $crdt.ORMap$<string>;
  /** @deprecated */
  own_tallies: $dict.Dict$<string, [number, number]>;
  /** @deprecated */
  authored_mv_registers: $dict.Dict$<string, $mv_register.MVRegister$<string>>;
  /** @deprecated */
  register_clock: $dict.Dict$<string, number>;
  /** @deprecated */
  set_clocks: $or_map_set_leaf.Clocks$;
  /** @deprecated */
  pending: _.List<PendingOperation$>;
  /** @deprecated */
  next_pending_message_id: number;
}
export function OrMapState$OrMapState(
  replica_id: $replica_id.ReplicaId$,
  mode: OrMapMode$,
  sequenced: $crdt.ORMap$<string>,
  optimistic: $crdt.ORMap$<string>,
  authored: $crdt.ORMap$<string>,
  own_tallies: $dict.Dict$<string, [number, number]>,
  authored_mv_registers: $dict.Dict$<string, $mv_register.MVRegister$<string>>,
  register_clock: $dict.Dict$<string, number>,
  set_clocks: $or_map_set_leaf.Clocks$,
  pending: _.List<PendingOperation$>,
  next_pending_message_id: number,
): OrMapState$;
export function OrMapState$isOrMapState(value: any): value is OrMapState$;
export function OrMapState$OrMapState$0(value: OrMapState$): $replica_id.ReplicaId$;
export function OrMapState$OrMapState$replica_id(
  value: OrMapState$,
): $replica_id.ReplicaId$;
export function OrMapState$OrMapState$1(value: OrMapState$): OrMapMode$;
export function OrMapState$OrMapState$mode(value: OrMapState$): OrMapMode$;
export function OrMapState$OrMapState$2(value: OrMapState$): $crdt.ORMap$<
  string
>;
export function OrMapState$OrMapState$sequenced(value: OrMapState$): $crdt.ORMap$<
  string
>;
export function OrMapState$OrMapState$3(value: OrMapState$): $crdt.ORMap$<
  string
>;
export function OrMapState$OrMapState$optimistic(value: OrMapState$): $crdt.ORMap$<
  string
>;
export function OrMapState$OrMapState$4(value: OrMapState$): $crdt.ORMap$<
  string
>;
export function OrMapState$OrMapState$authored(value: OrMapState$): $crdt.ORMap$<
  string
>;
export function OrMapState$OrMapState$5(value: OrMapState$): $dict.Dict$<
  string,
  [number, number]
>;
export function OrMapState$OrMapState$own_tallies(value: OrMapState$): $dict.Dict$<
  string,
  [number, number]
>;
export function OrMapState$OrMapState$6(value: OrMapState$): $dict.Dict$<
  string,
  $mv_register.MVRegister$<string>
>;
export function OrMapState$OrMapState$authored_mv_registers(value: OrMapState$): $dict.Dict$<
  string,
  $mv_register.MVRegister$<string>
>;
export function OrMapState$OrMapState$7(value: OrMapState$): $dict.Dict$<
  string,
  number
>;
export function OrMapState$OrMapState$register_clock(value: OrMapState$): $dict.Dict$<
  string,
  number
>;
export function OrMapState$OrMapState$8(value: OrMapState$): $or_map_set_leaf.Clocks$;
export function OrMapState$OrMapState$set_clocks(
  value: OrMapState$,
): $or_map_set_leaf.Clocks$;
export function OrMapState$OrMapState$9(value: OrMapState$): _.List<
  PendingOperation$
>;
export function OrMapState$OrMapState$pending(value: OrMapState$): _.List<
  PendingOperation$
>;
export function OrMapState$OrMapState$10(value: OrMapState$): number;
export function OrMapState$OrMapState$next_pending_message_id(value: OrMapState$): number;

export type OrMapState$ = OrMapState;

export class PendingOperation extends _.CustomType {
  /** @deprecated */
  constructor(operation: OrMapOperation$, message_id: number);
  /** @deprecated */
  operation: OrMapOperation$;
  /** @deprecated */
  message_id: number;
}
export function PendingOperation$PendingOperation(
  operation: OrMapOperation$,
  message_id: number,
): PendingOperation$;
export function PendingOperation$isPendingOperation(
  value: any,
): value is PendingOperation$;
export function PendingOperation$PendingOperation$0(value: PendingOperation$): OrMapOperation$;
export function PendingOperation$PendingOperation$operation(
  value: PendingOperation$,
): OrMapOperation$;
export function PendingOperation$PendingOperation$1(value: PendingOperation$): number;
export function PendingOperation$PendingOperation$message_id(
  value: PendingOperation$,
): number;

export type PendingOperation$ = PendingOperation;

export class Increment extends _.CustomType {
  /** @deprecated */
  constructor(key: string, amount: number, delta: $crdt.ORMapDelta$<string>);
  /** @deprecated */
  key: string;
  /** @deprecated */
  amount: number;
  /** @deprecated */
  delta: $crdt.ORMapDelta$<string>;
}
export function OrMapOperation$Increment(
  key: string,
  amount: number,
  delta: $crdt.ORMapDelta$<string>,
): OrMapOperation$;
export function OrMapOperation$isIncrement(
  value: any,
): value is OrMapOperation$;
export function OrMapOperation$Increment$0(value: OrMapOperation$): string;
export function OrMapOperation$Increment$key(value: OrMapOperation$): string;
export function OrMapOperation$Increment$1(value: OrMapOperation$): number;
export function OrMapOperation$Increment$amount(value: OrMapOperation$): number;
export function OrMapOperation$Increment$2(value: OrMapOperation$): $crdt.ORMapDelta$<
  string
>;
export function OrMapOperation$Increment$delta(value: OrMapOperation$): $crdt.ORMapDelta$<
  string
>;

export class SetRegister extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    value: string,
    timestamp: number,
    delta: $crdt.ORMapDelta$<string>
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: string;
  /** @deprecated */
  timestamp: number;
  /** @deprecated */
  delta: $crdt.ORMapDelta$<string>;
}
export function OrMapOperation$SetRegister(
  key: string,
  value: string,
  timestamp: number,
  delta: $crdt.ORMapDelta$<string>,
): OrMapOperation$;
export function OrMapOperation$isSetRegister(
  value: any,
): value is OrMapOperation$;
export function OrMapOperation$SetRegister$0(value: OrMapOperation$): string;
export function OrMapOperation$SetRegister$key(value: OrMapOperation$): string;
export function OrMapOperation$SetRegister$1(value: OrMapOperation$): string;
export function OrMapOperation$SetRegister$value(value: OrMapOperation$): string;
export function OrMapOperation$SetRegister$2(
  value: OrMapOperation$,
): number;
export function OrMapOperation$SetRegister$timestamp(value: OrMapOperation$): number;
export function OrMapOperation$SetRegister$3(
  value: OrMapOperation$,
): $crdt.ORMapDelta$<string>;
export function OrMapOperation$SetRegister$delta(value: OrMapOperation$): $crdt.ORMapDelta$<
  string
>;

export class SetMvRegister extends _.CustomType {
  /** @deprecated */
  constructor(key: string, value: string, delta: $crdt.ORMapDelta$<string>);
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: string;
  /** @deprecated */
  delta: $crdt.ORMapDelta$<string>;
}
export function OrMapOperation$SetMvRegister(
  key: string,
  value: string,
  delta: $crdt.ORMapDelta$<string>,
): OrMapOperation$;
export function OrMapOperation$isSetMvRegister(
  value: any,
): value is OrMapOperation$;
export function OrMapOperation$SetMvRegister$0(value: OrMapOperation$): string;
export function OrMapOperation$SetMvRegister$key(value: OrMapOperation$): string;
export function OrMapOperation$SetMvRegister$1(
  value: OrMapOperation$,
): string;
export function OrMapOperation$SetMvRegister$value(value: OrMapOperation$): string;
export function OrMapOperation$SetMvRegister$2(
  value: OrMapOperation$,
): $crdt.ORMapDelta$<string>;
export function OrMapOperation$SetMvRegister$delta(value: OrMapOperation$): $crdt.ORMapDelta$<
  string
>;

export class Remove extends _.CustomType {
  /** @deprecated */
  constructor(key: string, delta: $crdt.ORMapDelta$<string>);
  /** @deprecated */
  key: string;
  /** @deprecated */
  delta: $crdt.ORMapDelta$<string>;
}
export function OrMapOperation$Remove(
  key: string,
  delta: $crdt.ORMapDelta$<string>,
): OrMapOperation$;
export function OrMapOperation$isRemove(value: any): value is OrMapOperation$;
export function OrMapOperation$Remove$0(value: OrMapOperation$): string;
export function OrMapOperation$Remove$key(value: OrMapOperation$): string;
export function OrMapOperation$Remove$1(value: OrMapOperation$): $crdt.ORMapDelta$<
  string
>;
export function OrMapOperation$Remove$delta(value: OrMapOperation$): $crdt.ORMapDelta$<
  string
>;

export class AddMember extends _.CustomType {
  /** @deprecated */
  constructor(key: string, member: string, delta: $crdt.ORMapDelta$<string>);
  /** @deprecated */
  key: string;
  /** @deprecated */
  member: string;
  /** @deprecated */
  delta: $crdt.ORMapDelta$<string>;
}
export function OrMapOperation$AddMember(
  key: string,
  member: string,
  delta: $crdt.ORMapDelta$<string>,
): OrMapOperation$;
export function OrMapOperation$isAddMember(
  value: any,
): value is OrMapOperation$;
export function OrMapOperation$AddMember$0(value: OrMapOperation$): string;
export function OrMapOperation$AddMember$key(value: OrMapOperation$): string;
export function OrMapOperation$AddMember$1(value: OrMapOperation$): string;
export function OrMapOperation$AddMember$member(value: OrMapOperation$): string;
export function OrMapOperation$AddMember$2(value: OrMapOperation$): $crdt.ORMapDelta$<
  string
>;
export function OrMapOperation$AddMember$delta(value: OrMapOperation$): $crdt.ORMapDelta$<
  string
>;

export class RemoveMember extends _.CustomType {
  /** @deprecated */
  constructor(key: string, member: string, delta: $crdt.ORMapDelta$<string>);
  /** @deprecated */
  key: string;
  /** @deprecated */
  member: string;
  /** @deprecated */
  delta: $crdt.ORMapDelta$<string>;
}
export function OrMapOperation$RemoveMember(
  key: string,
  member: string,
  delta: $crdt.ORMapDelta$<string>,
): OrMapOperation$;
export function OrMapOperation$isRemoveMember(
  value: any,
): value is OrMapOperation$;
export function OrMapOperation$RemoveMember$0(value: OrMapOperation$): string;
export function OrMapOperation$RemoveMember$key(value: OrMapOperation$): string;
export function OrMapOperation$RemoveMember$1(value: OrMapOperation$): string;
export function OrMapOperation$RemoveMember$member(value: OrMapOperation$): string;
export function OrMapOperation$RemoveMember$2(
  value: OrMapOperation$,
): $crdt.ORMapDelta$<string>;
export function OrMapOperation$RemoveMember$delta(value: OrMapOperation$): $crdt.ORMapDelta$<
  string
>;

export type OrMapOperation$ = Increment | SetRegister | SetMvRegister | Remove | AddMember | RemoveMember;

export function OrMapOperation$key(value: OrMapOperation$): string;

export class TallyUpdated extends _.CustomType {
  /** @deprecated */
  constructor(key: string, applied: number, new_value: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  applied: number;
  /** @deprecated */
  new_value: number;
}
export function OrMapEvent$TallyUpdated(
  key: string,
  applied: number,
  new_value: number,
): OrMapEvent$;
export function OrMapEvent$isTallyUpdated(value: any): value is OrMapEvent$;
export function OrMapEvent$TallyUpdated$0(value: OrMapEvent$): string;
export function OrMapEvent$TallyUpdated$key(value: OrMapEvent$): string;
export function OrMapEvent$TallyUpdated$1(value: OrMapEvent$): number;
export function OrMapEvent$TallyUpdated$applied(value: OrMapEvent$): number;
export function OrMapEvent$TallyUpdated$2(value: OrMapEvent$): number;
export function OrMapEvent$TallyUpdated$new_value(value: OrMapEvent$): number;

export class RegisterUpdated extends _.CustomType {
  /** @deprecated */
  constructor(key: string, value: string);
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: string;
}
export function OrMapEvent$RegisterUpdated(
  key: string,
  value: string,
): OrMapEvent$;
export function OrMapEvent$isRegisterUpdated(value: any): value is OrMapEvent$;
export function OrMapEvent$RegisterUpdated$0(value: OrMapEvent$): string;
export function OrMapEvent$RegisterUpdated$key(value: OrMapEvent$): string;
export function OrMapEvent$RegisterUpdated$1(value: OrMapEvent$): string;
export function OrMapEvent$RegisterUpdated$value(value: OrMapEvent$): string;

export class SetMembersUpdated extends _.CustomType {
  /** @deprecated */
  constructor(key: string, members: _.List<string>);
  /** @deprecated */
  key: string;
  /** @deprecated */
  members: _.List<string>;
}
export function OrMapEvent$SetMembersUpdated(
  key: string,
  members: _.List<string>,
): OrMapEvent$;
export function OrMapEvent$isSetMembersUpdated(
  value: any,
): value is OrMapEvent$;
export function OrMapEvent$SetMembersUpdated$0(value: OrMapEvent$): string;
export function OrMapEvent$SetMembersUpdated$key(value: OrMapEvent$): string;
export function OrMapEvent$SetMembersUpdated$1(value: OrMapEvent$): _.List<
  string
>;
export function OrMapEvent$SetMembersUpdated$members(value: OrMapEvent$): _.List<
  string
>;

export class MvRegisterUpdated extends _.CustomType {
  /** @deprecated */
  constructor(key: string, values: _.List<string>);
  /** @deprecated */
  key: string;
  /** @deprecated */
  values: _.List<string>;
}
export function OrMapEvent$MvRegisterUpdated(
  key: string,
  values: _.List<string>,
): OrMapEvent$;
export function OrMapEvent$isMvRegisterUpdated(
  value: any,
): value is OrMapEvent$;
export function OrMapEvent$MvRegisterUpdated$0(value: OrMapEvent$): string;
export function OrMapEvent$MvRegisterUpdated$key(value: OrMapEvent$): string;
export function OrMapEvent$MvRegisterUpdated$1(value: OrMapEvent$): _.List<
  string
>;
export function OrMapEvent$MvRegisterUpdated$values(value: OrMapEvent$): _.List<
  string
>;

export class KeyRemoved extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function OrMapEvent$KeyRemoved(key: string): OrMapEvent$;
export function OrMapEvent$isKeyRemoved(value: any): value is OrMapEvent$;
export function OrMapEvent$KeyRemoved$0(value: OrMapEvent$): string;
export function OrMapEvent$KeyRemoved$key(value: OrMapEvent$): string;

export type OrMapEvent$ = TallyUpdated | RegisterUpdated | SetMembersUpdated | MvRegisterUpdated | KeyRemoved;

export function OrMapEvent$key(value: OrMapEvent$): string;

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

export class ModeMismatch extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$ModeMismatch(detail: string): KernelError$;
export function KernelError$isModeMismatch(value: any): value is KernelError$;
export function KernelError$ModeMismatch$0(value: KernelError$): string;
export function KernelError$ModeMismatch$detail(value: KernelError$): string;

export class CorruptDelta extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$CorruptDelta(detail: string): KernelError$;
export function KernelError$isCorruptDelta(value: any): value is KernelError$;
export function KernelError$CorruptDelta$0(value: KernelError$): string;
export function KernelError$CorruptDelta$detail(value: KernelError$): string;

export class InvalidSetState extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$InvalidSetState(detail: string): KernelError$;
export function KernelError$isInvalidSetState(
  value: any,
): value is KernelError$;
export function KernelError$InvalidSetState$0(value: KernelError$): string;
export function KernelError$InvalidSetState$detail(value: KernelError$): string;

export class CounterExhausted extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$CounterExhausted(detail: string): KernelError$;
export function KernelError$isCounterExhausted(
  value: any,
): value is KernelError$;
export function KernelError$CounterExhausted$0(value: KernelError$): string;
export function KernelError$CounterExhausted$detail(value: KernelError$): string;

export class NegativeTally extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function KernelError$NegativeTally(detail: string): KernelError$;
export function KernelError$isNegativeTally(value: any): value is KernelError$;
export function KernelError$NegativeTally$0(value: KernelError$): string;
export function KernelError$NegativeTally$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAck | UnexpectedRollback | ModeMismatch | CorruptDelta | InvalidSetState | CounterExhausted | NegativeTally;

export function KernelError$detail(value: KernelError$): string;

declare class KeyDelta extends _.CustomType {
  /** @deprecated */
  constructor(
    author: string,
    counter: number,
    entries: $dict.Dict$<string, _.List<[string, number]>>,
    tombstones: _.List<[string, number]>,
    pruned: $version_vector.VersionVector$
  );
  /** @deprecated */
  author: string;
  /** @deprecated */
  counter: number;
  /** @deprecated */
  entries: $dict.Dict$<string, _.List<[string, number]>>;
  /** @deprecated */
  tombstones: _.List<[string, number]>;
  /** @deprecated */
  pruned: $version_vector.VersionVector$;
}

type KeyDelta$ = KeyDelta;

export type ORMap = $crdt.ORMap$<string>;

export type ORMapDelta = $crdt.ORMapDelta$<string>;

export function mode_to_spec(mode: OrMapMode$): $crdt.CrdtSpec$<string>;

export function spec_string_to_mode(spec: string): _.Result<
  OrMapMode$,
  undefined
>;

export function new$(replica_id: $replica_id.ReplicaId$, mode: OrMapMode$): OrMapState$;

export function entries(state: OrMapState$): _.List<[string, OrMapValue$]>;

export function keys(state: OrMapState$): _.List<string>;

export function get(state: OrMapState$, key: string): _.Result<
  OrMapValue$,
  undefined
>;

export function sequenced_entries(state: OrMapState$): _.List<
  [string, OrMapValue$]
>;

export function increment(state: OrMapState$, key: string, amount: number): _.Result<
  [OrMapState$, _.List<OrMapEvent$>, OrMapOperation$, number],
  KernelError$
>;

export function set_register(
  state: OrMapState$,
  key: string,
  value: string,
  timestamp: number
): _.Result<
  [OrMapState$, _.List<OrMapEvent$>, OrMapOperation$, number],
  KernelError$
>;

export function validate_operation(mode: OrMapMode$, operation: OrMapOperation$): _.Result<
  undefined,
  KernelError$
>;

export function remove(state: OrMapState$, key: string): _.Result<
  [OrMapState$, _.List<OrMapEvent$>, OrMapOperation$, number],
  KernelError$
>;

export function p2p_increment(state: OrMapState$, key: string, amount: number): _.Result<
  [OrMapState$, _.List<OrMapEvent$>, OrMapOperation$],
  KernelError$
>;

export function p2p_set_register(
  state: OrMapState$,
  key: string,
  value: string,
  timestamp: number
): _.Result<[OrMapState$, _.List<OrMapEvent$>, OrMapOperation$], KernelError$>;

export function set_mv_register(state: OrMapState$, key: string, value: string): _.Result<
  [OrMapState$, _.List<OrMapEvent$>, OrMapOperation$, number],
  KernelError$
>;

export function p2p_set_mv_register(
  state: OrMapState$,
  key: string,
  value: string
): _.Result<[OrMapState$, _.List<OrMapEvent$>, OrMapOperation$], KernelError$>;

export function p2p_remove(state: OrMapState$, key: string): _.Result<
  [OrMapState$, _.List<OrMapEvent$>, OrMapOperation$],
  KernelError$
>;

export function add_member(state: OrMapState$, key: string, member: string): _.Result<
  [OrMapState$, _.List<OrMapEvent$>, OrMapOperation$, number],
  KernelError$
>;

export function remove_member(state: OrMapState$, key: string, member: string): _.Result<
  [OrMapState$, _.List<OrMapEvent$>, OrMapOperation$, number],
  KernelError$
>;

export function p2p_add_member(state: OrMapState$, key: string, member: string): _.Result<
  [OrMapState$, _.List<OrMapEvent$>, OrMapOperation$],
  KernelError$
>;

export function p2p_remove_member(
  state: OrMapState$,
  key: string,
  member: string
): _.Result<[OrMapState$, _.List<OrMapEvent$>, OrMapOperation$], KernelError$>;

export function p2p_merge(state: OrMapState$, other: $crdt.ORMap$<string>): _.Result<
  [OrMapState$, _.List<OrMapEvent$>],
  KernelError$
>;

export function apply_remote(state: OrMapState$, operation: OrMapOperation$): _.Result<
  [OrMapState$, _.List<OrMapEvent$>],
  KernelError$
>;

export function ack_local(state: OrMapState$, operation: OrMapOperation$): _.Result<
  OrMapState$,
  KernelError$
>;

export function ack_local_with_message_id(
  state: OrMapState$,
  operation: OrMapOperation$,
  message_id: number
): _.Result<OrMapState$, KernelError$>;

export function rollback(
  state: OrMapState$,
  operation: OrMapOperation$,
  message_id: number
): _.Result<[OrMapState$, _.List<OrMapEvent$>], KernelError$>;

export function apply_stashed_operation(
  state: OrMapState$,
  operation: OrMapOperation$
): _.Result<
  [OrMapState$, _.List<OrMapEvent$>, OrMapOperation$, number],
  KernelError$
>;

export function promote_attach(state: OrMapState$): OrMapState$;

export function summary(state: OrMapState$): $json.Json$;

export function from_sequenced(
  sequenced: $crdt.ORMap$<string>,
  mode: OrMapMode$,
  replica_id: $replica_id.ReplicaId$
): _.Result<OrMapState$, KernelError$>;

export function from_summary(
  summary_json: string,
  replica_id: $replica_id.ReplicaId$
): _.Result<OrMapState$, $json.DecodeError$>;

export function check_cache_coherence(state: OrMapState$): _.Result<
  undefined,
  string
>;

export function validate_operation_intent(operation: OrMapOperation$): _.Result<
  undefined,
  KernelError$
>;
