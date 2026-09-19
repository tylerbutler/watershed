import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $version_vector from "../../lattice_core/lattice_core/version_vector.d.mts";
import type * as $g_counter from "../../lattice_counters/lattice_counters/g_counter.d.mts";
import type * as $pn_counter from "../../lattice_counters/lattice_counters/pn_counter.d.mts";
import type * as $lww_register from "../../lattice_registers/lattice_registers/lww_register.d.mts";
import type * as $mv_register from "../../lattice_registers/lattice_registers/mv_register.d.mts";
import type * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.d.mts";
import type * as $g_set from "../../lattice_sets/lattice_sets/g_set.d.mts";
import type * as $or_set from "../../lattice_sets/lattice_sets/or_set.d.mts";
import type * as $two_p_set from "../../lattice_sets/lattice_sets/two_p_set.d.mts";
import type * as $text from "../../lattice_text/lattice_text/text.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $lww_map_engine from "../lattice_maps/internal/lww_map_engine.d.mts";
import type * as $or_map_engine from "../lattice_maps/internal/or_map_engine.d.mts";

export class CrdtGCounter extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $g_counter.GCounter$);
  /** @deprecated */
  0: $g_counter.GCounter$;
}
export function Crdt$CrdtGCounter<PPF>($0: $g_counter.GCounter$): Crdt$<PPF>;
export function Crdt$isCrdtGCounter<PPF>(value: any): value is Crdt$<unknown>;
export function Crdt$CrdtGCounter$0<PPF>(value: Crdt$<PPF>): $g_counter.GCounter$;

export class CrdtPnCounter extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $pn_counter.PNCounter$);
  /** @deprecated */
  0: $pn_counter.PNCounter$;
}
export function Crdt$CrdtPnCounter<PPF>($0: $pn_counter.PNCounter$): Crdt$<PPF>;
export function Crdt$isCrdtPnCounter<PPF>(value: any): value is Crdt$<unknown>;
export function Crdt$CrdtPnCounter$0<PPF>(value: Crdt$<PPF>): $pn_counter.PNCounter$;

export class CrdtLwwRegister<PPF> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $lww_register.LWWRegister$<PPF>);
  /** @deprecated */
  0: $lww_register.LWWRegister$<PPF>;
}
export function Crdt$CrdtLwwRegister<PPF>(
  $0: $lww_register.LWWRegister$<PPF>,
): Crdt$<PPF>;
export function Crdt$isCrdtLwwRegister<PPF>(
  value: any,
): value is Crdt$<unknown>;
export function Crdt$CrdtLwwRegister$0<PPF>(value: Crdt$<PPF>): $lww_register.LWWRegister$<
  PPF
>;

export class CrdtMvRegister<PPF> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $mv_register.MVRegister$<PPF>);
  /** @deprecated */
  0: $mv_register.MVRegister$<PPF>;
}
export function Crdt$CrdtMvRegister<PPF>(
  $0: $mv_register.MVRegister$<PPF>,
): Crdt$<PPF>;
export function Crdt$isCrdtMvRegister<PPF>(value: any): value is Crdt$<unknown>;
export function Crdt$CrdtMvRegister$0<PPF>(value: Crdt$<PPF>): $mv_register.MVRegister$<
  PPF
>;

export class CrdtGSet<PPF> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $g_set.GSet$<PPF>);
  /** @deprecated */
  0: $g_set.GSet$<PPF>;
}
export function Crdt$CrdtGSet<PPF>($0: $g_set.GSet$<PPF>): Crdt$<PPF>;
export function Crdt$isCrdtGSet<PPF>(value: any): value is Crdt$<unknown>;
export function Crdt$CrdtGSet$0<PPF>(value: Crdt$<PPF>): $g_set.GSet$<PPF>;

export class CrdtTwoPSet<PPF> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $two_p_set.TwoPSet$<PPF>);
  /** @deprecated */
  0: $two_p_set.TwoPSet$<PPF>;
}
export function Crdt$CrdtTwoPSet<PPF>($0: $two_p_set.TwoPSet$<PPF>): Crdt$<PPF>;
export function Crdt$isCrdtTwoPSet<PPF>(value: any): value is Crdt$<unknown>;
export function Crdt$CrdtTwoPSet$0<PPF>(value: Crdt$<PPF>): $two_p_set.TwoPSet$<
  PPF
>;

export class CrdtOrSet<PPF> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $or_set.ORSet$<PPF>);
  /** @deprecated */
  0: $or_set.ORSet$<PPF>;
}
export function Crdt$CrdtOrSet<PPF>($0: $or_set.ORSet$<PPF>): Crdt$<PPF>;
export function Crdt$isCrdtOrSet<PPF>(value: any): value is Crdt$<unknown>;
export function Crdt$CrdtOrSet$0<PPF>(value: Crdt$<PPF>): $or_set.ORSet$<PPF>;

export class CrdtVersionVector extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $version_vector.VersionVector$);
  /** @deprecated */
  0: $version_vector.VersionVector$;
}
export function Crdt$CrdtVersionVector<PPF>(
  $0: $version_vector.VersionVector$,
): Crdt$<PPF>;
export function Crdt$isCrdtVersionVector<PPF>(
  value: any,
): value is Crdt$<unknown>;
export function Crdt$CrdtVersionVector$0<PPF>(value: Crdt$<PPF>): $version_vector.VersionVector$;

export class CrdtSequence<PPF> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $sequence.Sequence$<PPF>);
  /** @deprecated */
  0: $sequence.Sequence$<PPF>;
}
export function Crdt$CrdtSequence<PPF>(
  $0: $sequence.Sequence$<PPF>,
): Crdt$<PPF>;
export function Crdt$isCrdtSequence<PPF>(value: any): value is Crdt$<unknown>;
export function Crdt$CrdtSequence$0<PPF>(value: Crdt$<PPF>): $sequence.Sequence$<
  PPF
>;

export class CrdtText extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $text.Text$);
  /** @deprecated */
  0: $text.Text$;
}
export function Crdt$CrdtText<PPF>($0: $text.Text$): Crdt$<PPF>;
export function Crdt$isCrdtText<PPF>(value: any): value is Crdt$<unknown>;
export function Crdt$CrdtText$0<PPF>(value: Crdt$<PPF>): $text.Text$;

export class CrdtOrMap<PPF> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: ORMap$<PPF>);
  /** @deprecated */
  0: ORMap$<PPF>;
}
export function Crdt$CrdtOrMap<PPF>($0: ORMap$<PPF>): Crdt$<PPF>;
export function Crdt$isCrdtOrMap<PPF>(value: any): value is Crdt$<unknown>;
export function Crdt$CrdtOrMap$0<PPF>(value: Crdt$<PPF>): ORMap$<PPF>;

export class CrdtLwwMap<PPF> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: LWWMap$<PPF>);
  /** @deprecated */
  0: LWWMap$<PPF>;
}
export function Crdt$CrdtLwwMap<PPF>($0: LWWMap$<PPF>): Crdt$<PPF>;
export function Crdt$isCrdtLwwMap<PPF>(value: any): value is Crdt$<unknown>;
export function Crdt$CrdtLwwMap$0<PPF>(value: Crdt$<PPF>): LWWMap$<PPF>;

export type Crdt$<PPF> = CrdtGCounter | CrdtPnCounter | CrdtLwwRegister<PPF> | CrdtMvRegister<
  PPF
> | CrdtGSet<PPF> | CrdtTwoPSet<PPF> | CrdtOrSet<PPF> | CrdtVersionVector | CrdtSequence<
  PPF
> | CrdtText | CrdtOrMap<PPF> | CrdtLwwMap<PPF>;

export class GCounterSpec extends _.CustomType {}
export function CrdtSpec$GCounterSpec<PPG>(): CrdtSpec$<PPG>;
export function CrdtSpec$isGCounterSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;

export class PnCounterSpec extends _.CustomType {}
export function CrdtSpec$PnCounterSpec<PPG>(): CrdtSpec$<PPG>;
export function CrdtSpec$isPnCounterSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;

export class LwwRegisterSpec<PPG> extends _.CustomType {
  /** @deprecated */
  constructor(initial_value: PPG);
  /** @deprecated */
  initial_value: PPG;
}
export function CrdtSpec$LwwRegisterSpec<PPG>(
  initial_value: PPG,
): CrdtSpec$<PPG>;
export function CrdtSpec$isLwwRegisterSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;
export function CrdtSpec$LwwRegisterSpec$0<PPG>(value: CrdtSpec$<PPG>): PPG;
export function CrdtSpec$LwwRegisterSpec$initial_value<PPG>(value: CrdtSpec$<
    PPG
  >): PPG;

export class MvRegisterSpec extends _.CustomType {}
export function CrdtSpec$MvRegisterSpec<PPG>(): CrdtSpec$<PPG>;
export function CrdtSpec$isMvRegisterSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;

export class GSetSpec extends _.CustomType {}
export function CrdtSpec$GSetSpec<PPG>(): CrdtSpec$<PPG>;
export function CrdtSpec$isGSetSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;

export class TwoPSetSpec extends _.CustomType {}
export function CrdtSpec$TwoPSetSpec<PPG>(): CrdtSpec$<PPG>;
export function CrdtSpec$isTwoPSetSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;

export class OrSetSpec extends _.CustomType {}
export function CrdtSpec$OrSetSpec<PPG>(): CrdtSpec$<PPG>;
export function CrdtSpec$isOrSetSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;

export class SequenceSpec extends _.CustomType {}
export function CrdtSpec$SequenceSpec<PPG>(): CrdtSpec$<PPG>;
export function CrdtSpec$isSequenceSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;

export class TextSpec extends _.CustomType {}
export function CrdtSpec$TextSpec<PPG>(): CrdtSpec$<PPG>;
export function CrdtSpec$isTextSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;

export class OrMapSpec<PPG> extends _.CustomType {
  /** @deprecated */
  constructor(child_spec: CrdtSpec$<PPG>);
  /** @deprecated */
  child_spec: CrdtSpec$<PPG>;
}
export function CrdtSpec$OrMapSpec<PPG>(
  child_spec: CrdtSpec$<PPG>,
): CrdtSpec$<PPG>;
export function CrdtSpec$isOrMapSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;
export function CrdtSpec$OrMapSpec$0<PPG>(value: CrdtSpec$<PPG>): CrdtSpec$<PPG>;
export function CrdtSpec$OrMapSpec$child_spec<PPG>(
  value: CrdtSpec$<PPG>,
): CrdtSpec$<PPG>;

export class LwwMapSpec<PPG> extends _.CustomType {
  /** @deprecated */
  constructor(child_spec: CrdtSpec$<PPG>);
  /** @deprecated */
  child_spec: CrdtSpec$<PPG>;
}
export function CrdtSpec$LwwMapSpec<PPG>(
  child_spec: CrdtSpec$<PPG>,
): CrdtSpec$<PPG>;
export function CrdtSpec$isLwwMapSpec<PPG>(
  value: any,
): value is CrdtSpec$<unknown>;
export function CrdtSpec$LwwMapSpec$0<PPG>(value: CrdtSpec$<PPG>): CrdtSpec$<
  PPG
>;
export function CrdtSpec$LwwMapSpec$child_spec<PPG>(value: CrdtSpec$<PPG>): CrdtSpec$<
  PPG
>;

export type CrdtSpec$<PPG> = GCounterSpec | PnCounterSpec | LwwRegisterSpec<PPG> | MvRegisterSpec | GSetSpec | TwoPSetSpec | OrSetSpec | SequenceSpec | TextSpec | OrMapSpec<
  PPG
> | LwwMapSpec<PPG>;

export class NoChange<PPH> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: CrdtSpec$<PPH>);
  /** @deprecated */
  0: CrdtSpec$<PPH>;
}
export function CrdtDelta$NoChange<PPH>($0: CrdtSpec$<PPH>): CrdtDelta$<PPH>;
export function CrdtDelta$isNoChange<PPH>(
  value: any,
): value is CrdtDelta$<unknown>;
export function CrdtDelta$NoChange$0<PPH>(value: CrdtDelta$<PPH>): CrdtSpec$<
  PPH
>;

export class StateDelta<PPH> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: Crdt$<PPH>);
  /** @deprecated */
  0: Crdt$<PPH>;
}
export function CrdtDelta$StateDelta<PPH>($0: Crdt$<PPH>): CrdtDelta$<PPH>;
export function CrdtDelta$isStateDelta<PPH>(
  value: any,
): value is CrdtDelta$<unknown>;
export function CrdtDelta$StateDelta$0<PPH>(value: CrdtDelta$<PPH>): Crdt$<PPH>;

export class OrMapChange<PPH> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: ORMapDelta$<PPH>);
  /** @deprecated */
  0: ORMapDelta$<PPH>;
}
export function CrdtDelta$OrMapChange<PPH>(
  $0: ORMapDelta$<PPH>,
): CrdtDelta$<PPH>;
export function CrdtDelta$isOrMapChange<PPH>(
  value: any,
): value is CrdtDelta$<unknown>;
export function CrdtDelta$OrMapChange$0<PPH>(value: CrdtDelta$<PPH>): ORMapDelta$<
  PPH
>;

export type CrdtDelta$<PPH> = NoChange<PPH> | StateDelta<PPH> | OrMapChange<PPH>;

declare class ORMap<PPI> extends _.CustomType {
  /** @deprecated */
  constructor(
    replica: $replica_id.ReplicaId$,
    spec: CrdtSpec$<PPI>,
    state: $observed.State$<Crdt$<PPI>>
  );
  /** @deprecated */
  replica: $replica_id.ReplicaId$;
  /** @deprecated */
  spec: CrdtSpec$<PPI>;
  /** @deprecated */
  state: $observed.State$<Crdt$<PPI>>;
}

export type ORMap$<PPI> = ORMap<PPI>;

declare class ORMapDelta<PPJ> extends _.CustomType {
  /** @deprecated */
  constructor(
    replica: $replica_id.ReplicaId$,
    spec: CrdtSpec$<PPJ>,
    state: $observed.State$<CrdtDelta$<PPJ>>
  );
  /** @deprecated */
  replica: $replica_id.ReplicaId$;
  /** @deprecated */
  spec: CrdtSpec$<PPJ>;
  /** @deprecated */
  state: $observed.State$<CrdtDelta$<PPJ>>;
}

export type ORMapDelta$<PPJ> = ORMapDelta<PPJ>;

declare class LWWMap<PPK> extends _.CustomType {
  /** @deprecated */
  constructor(
    replica: $replica_id.ReplicaId$,
    spec: CrdtSpec$<PPK>,
    state: $lww.State$<Crdt$<PPK>>
  );
  /** @deprecated */
  replica: $replica_id.ReplicaId$;
  /** @deprecated */
  spec: CrdtSpec$<PPK>;
  /** @deprecated */
  state: $lww.State$<Crdt$<PPK>>;
}

export type LWWMap$<PPK> = LWWMap<PPK>;

export class TypeMismatch extends _.CustomType {
  /** @deprecated */
  constructor(expected: string, found: string);
  /** @deprecated */
  expected: string;
  /** @deprecated */
  found: string;
}
export function MergeError$TypeMismatch(
  expected: string,
  found: string,
): MergeError$;
export function MergeError$isTypeMismatch(value: any): value is MergeError$;
export function MergeError$TypeMismatch$0(value: MergeError$): string;
export function MergeError$TypeMismatch$expected(value: MergeError$): string;
export function MergeError$TypeMismatch$1(value: MergeError$): string;
export function MergeError$TypeMismatch$found(value: MergeError$): string;

export class SchemaMismatch extends _.CustomType {}
export function MergeError$SchemaMismatch(): MergeError$;
export function MergeError$isSchemaMismatch(value: any): value is MergeError$;

export class AtKey extends _.CustomType {
  /** @deprecated */
  constructor(key: string, cause: MergeError$);
  /** @deprecated */
  key: string;
  /** @deprecated */
  cause: MergeError$;
}
export function MergeError$AtKey(key: string, cause: MergeError$): MergeError$;
export function MergeError$isAtKey(value: any): value is MergeError$;
export function MergeError$AtKey$0(value: MergeError$): string;
export function MergeError$AtKey$key(value: MergeError$): string;
export function MergeError$AtKey$1(value: MergeError$): MergeError$;
export function MergeError$AtKey$cause(value: MergeError$): MergeError$;

export class TimestampNotAdvanced extends _.CustomType {
  /** @deprecated */
  constructor(key: string, timestamp: number, floor: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  timestamp: number;
  /** @deprecated */
  floor: number;
}
export function MergeError$TimestampNotAdvanced(
  key: string,
  timestamp: number,
  floor: number,
): MergeError$;
export function MergeError$isTimestampNotAdvanced(
  value: any,
): value is MergeError$;
export function MergeError$TimestampNotAdvanced$0(value: MergeError$): string;
export function MergeError$TimestampNotAdvanced$key(value: MergeError$): string;
export function MergeError$TimestampNotAdvanced$1(value: MergeError$): number;
export function MergeError$TimestampNotAdvanced$timestamp(value: MergeError$): number;
export function MergeError$TimestampNotAdvanced$2(
  value: MergeError$,
): number;
export function MergeError$TimestampNotAdvanced$floor(value: MergeError$): number;

export class ConflictingWrite extends _.CustomType {
  /** @deprecated */
  constructor(key: string, timestamp: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  timestamp: number;
}
export function MergeError$ConflictingWrite(
  key: string,
  timestamp: number,
): MergeError$;
export function MergeError$isConflictingWrite(value: any): value is MergeError$;
export function MergeError$ConflictingWrite$0(value: MergeError$): string;
export function MergeError$ConflictingWrite$key(value: MergeError$): string;
export function MergeError$ConflictingWrite$1(value: MergeError$): number;
export function MergeError$ConflictingWrite$timestamp(value: MergeError$): number;

export class ClockExhausted extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function MergeError$ClockExhausted(key: string): MergeError$;
export function MergeError$isClockExhausted(value: any): value is MergeError$;
export function MergeError$ClockExhausted$0(value: MergeError$): string;
export function MergeError$ClockExhausted$key(value: MergeError$): string;

export class InvalidTimestamp extends _.CustomType {
  /** @deprecated */
  constructor(key: string, timestamp: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  timestamp: number;
}
export function MergeError$InvalidTimestamp(
  key: string,
  timestamp: number,
): MergeError$;
export function MergeError$isInvalidTimestamp(value: any): value is MergeError$;
export function MergeError$InvalidTimestamp$0(value: MergeError$): string;
export function MergeError$InvalidTimestamp$key(value: MergeError$): string;
export function MergeError$InvalidTimestamp$1(value: MergeError$): number;
export function MergeError$InvalidTimestamp$timestamp(value: MergeError$): number;

export type MergeError$ = TypeMismatch | SchemaMismatch | AtKey | TimestampNotAdvanced | ConflictingWrite | ClockExhausted | InvalidTimestamp;

export class CallbackError<PPL> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: PPL);
  /** @deprecated */
  0: PPL;
}
export function UpdateError$CallbackError<PPL>($0: PPL): UpdateError$<PPL>;
export function UpdateError$isCallbackError<PPL>(
  value: any,
): value is UpdateError$<unknown>;
export function UpdateError$CallbackError$0<PPL>(value: UpdateError$<PPL>): PPL;

export class CompositionError extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: MergeError$);
  /** @deprecated */
  0: MergeError$;
}
export function UpdateError$CompositionError<PPL>(
  $0: MergeError$,
): UpdateError$<PPL>;
export function UpdateError$isCompositionError<PPL>(
  value: any,
): value is UpdateError$<unknown>;
export function UpdateError$CompositionError$0<PPL>(value: UpdateError$<PPL>): MergeError$;

export type UpdateError$<PPL> = CallbackError<PPL> | CompositionError;

export class EditContext extends _.CustomType {
  /** @deprecated */
  constructor(replica_id: $replica_id.ReplicaId$);
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
}
export function EditContext$EditContext(
  replica_id: $replica_id.ReplicaId$,
): EditContext$;
export function EditContext$isEditContext(value: any): value is EditContext$;
export function EditContext$EditContext$0(value: EditContext$): $replica_id.ReplicaId$;
export function EditContext$EditContext$replica_id(
  value: EditContext$,
): $replica_id.ReplicaId$;

export type EditContext$ = EditContext;

export function type_name(value: Crdt$<any>): string;

export function spec_name(spec: CrdtSpec$<any>): string;

export function lww_new<PUV>(
  replica: $replica_id.ReplicaId$,
  spec: CrdtSpec$<PUV>
): LWWMap$<PUV>;

export function or_new<PRV>(
  replica: $replica_id.ReplicaId$,
  spec: CrdtSpec$<PRV>
): ORMap$<PRV>;

export function default_crdt<PPQ>(
  spec: CrdtSpec$<PPQ>,
  replica: $replica_id.ReplicaId$
): Crdt$<PPQ>;

export function matches_spec<PPT>(value: Crdt$<PPT>, spec: CrdtSpec$<PPT>): boolean;

export function default_delta<PQG>(
  spec: CrdtSpec$<PQG>,
  x1: $replica_id.ReplicaId$
): CrdtDelta$<PQG>;

export function is_empty_delta(value: CrdtDelta$<any>): boolean;

export function lww_bind<PVD>(
  map: LWWMap$<PVD>,
  replica: $replica_id.ReplicaId$
): LWWMap$<PVD>;

export function or_bind<PSD>(map: ORMap$<PSD>, replica: $replica_id.ReplicaId$): ORMap$<
  PSD
>;

export function bind<PQL>(value: Crdt$<PQL>, replica: $replica_id.ReplicaId$): Crdt$<
  PQL
>;

export function lww_merge_as<PWV>(
  a: LWWMap$<PWV>,
  b: LWWMap$<PWV>,
  replica: $replica_id.ReplicaId$
): _.Result<LWWMap$<PWV>, MergeError$>;

export function or_merge_as<PUA>(
  a: ORMap$<PUA>,
  b: ORMap$<PUA>,
  replica: $replica_id.ReplicaId$
): _.Result<ORMap$<PUA>, MergeError$>;

export function merge<PQO>(
  a: Crdt$<PQO>,
  b: Crdt$<PQO>,
  replica: $replica_id.ReplicaId$
): _.Result<Crdt$<PQO>, MergeError$>;

export function matches_delta<PQU>(delta: CrdtDelta$<PQU>, spec: CrdtSpec$<PQU>): boolean;

export function or_apply_delta<PUG>(map: ORMap$<PUG>, delta: ORMapDelta$<PUG>): _.Result<
  ORMap$<PUG>,
  MergeError$
>;

export function apply_delta<PRC>(
  value: Crdt$<PRC>,
  delta: CrdtDelta$<PRC>,
  spec: CrdtSpec$<PRC>,
  replica: $replica_id.ReplicaId$
): _.Result<Crdt$<PRC>, MergeError$>;

export function or_merge_deltas<PUM>(a: ORMapDelta$<PUM>, b: ORMapDelta$<PUM>): _.Result<
  ORMapDelta$<PUM>,
  MergeError$
>;

export function merge_deltas<PRJ>(
  a: CrdtDelta$<PRJ>,
  b: CrdtDelta$<PRJ>,
  spec: CrdtSpec$<PRJ>,
  replica: $replica_id.ReplicaId$
): _.Result<CrdtDelta$<PRJ>, MergeError$>;

export function or_replica(map: ORMap$<any>): $replica_id.ReplicaId$;

export function or_spec<PSA>(map: ORMap$<PSA>): CrdtSpec$<PSA>;

export function or_get<PSL>(map: ORMap$<PSL>, key: string): _.Result<
  Crdt$<PSL>,
  undefined
>;

export function or_keys(map: ORMap$<any>): _.List<string>;

export function or_values<PST>(map: ORMap$<PST>): _.List<Crdt$<PST>>;

export function or_value_count(map: ORMap$<any>): number;

export function or_empty_delta<PSZ>(map: ORMap$<PSZ>): ORMapDelta$<PSZ>;

export function or_update_delta<PTC, PTG>(
  map: ORMap$<PTC>,
  key: string,
  callback: (x0: Crdt$<PTC>, x1: EditContext$) => _.Result<CrdtDelta$<PTC>, PTG>
): _.Result<[ORMap$<PTC>, ORMapDelta$<PTC>], UpdateError$<PTG>>;

export function or_update_with_delta<PTO>(
  map: ORMap$<PTO>,
  key: string,
  callback: (x0: Crdt$<PTO>) => Crdt$<PTO>
): _.Result<[ORMap$<PTO>, ORMapDelta$<PTO>], MergeError$>;

export function or_remove_with_delta<PTW>(map: ORMap$<PTW>, key: string): [
  ORMap$<PTW>,
  ORMapDelta$<PTW>
];

export function or_prune<PUS>(
  map: ORMap$<PUS>,
  stable: $version_vector.VersionVector$
): ORMap$<PUS>;

export function lww_replica(map: LWWMap$<any>): $replica_id.ReplicaId$;

export function lww_spec<PVA>(map: LWWMap$<PVA>): CrdtSpec$<PVA>;

export function lww_get<PVG>(map: LWWMap$<PVG>, key: string): _.Result<
  Crdt$<PVG>,
  undefined
>;

export function lww_set<PVL>(
  map: LWWMap$<PVL>,
  key: string,
  value: Crdt$<PVL>,
  timestamp: number
): _.Result<LWWMap$<PVL>, MergeError$>;

export function lww_update<PVR, PVV>(
  map: LWWMap$<PVR>,
  key: string,
  timestamp: number,
  callback: (x0: Crdt$<PVR>, x1: EditContext$) => _.Result<Crdt$<PVR>, PVV>
): _.Result<LWWMap$<PVR>, UpdateError$<PVV>>;

export function lww_remove<PWC>(
  map: LWWMap$<PWC>,
  key: string,
  timestamp: number
): _.Result<LWWMap$<PWC>, MergeError$>;

export function lww_keys(map: LWWMap$<any>): _.List<string>;

export function lww_values<PWK>(map: LWWMap$<PWK>): _.List<Crdt$<PWK>>;

export function lww_tombstone_count(map: LWWMap$<any>): number;

export function lww_pruned_timestamp(map: LWWMap$<any>): number;

export function lww_prune<PWS>(map: LWWMap$<PWS>, stable: number): LWWMap$<PWS>;

export function spec_to_json_with<PXU>(
  spec: CrdtSpec$<PXU>,
  encode: (x0: PXU) => $json.Json$
): $json.Json$;

export function spec_from_json_with<PXW>(
  input: string,
  decoder: $decode.Decoder$<PXW>
): _.Result<CrdtSpec$<PXW>, $json.DecodeError$>;

export function lww_to_json_with<QAO>(
  map: LWWMap$<QAO>,
  encode: (x0: QAO) => $json.Json$
): $json.Json$;

export function or_to_json_with<PZJ>(
  map: ORMap$<PZJ>,
  encode: (x0: PZJ) => $json.Json$
): $json.Json$;

export function to_json_with<PYC>(
  value: Crdt$<PYC>,
  encode: (x0: PYC) => $json.Json$
): $json.Json$;

export function to_json(value: Crdt$<string>): $json.Json$;

export function lww_from_json_with<QAQ>(
  input: string,
  decoder: $decode.Decoder$<QAQ>
): _.Result<LWWMap$<QAQ>, $json.DecodeError$>;

export function or_from_json_with<QAD>(
  input: string,
  decoder: $decode.Decoder$<QAD>
): _.Result<ORMap$<QAD>, $json.DecodeError$>;

export function from_json_with<PYO>(
  input: string,
  decoder: $decode.Decoder$<PYO>
): _.Result<Crdt$<PYO>, $json.DecodeError$>;

export function from_json(input: string): _.Result<
  Crdt$<string>,
  $json.DecodeError$
>;

export function or_delta_to_json_with<PZL>(
  delta: ORMapDelta$<PZL>,
  encode: (x0: PZL) => $json.Json$
): $json.Json$;

export function delta_to_json_with<PYU>(
  delta: CrdtDelta$<PYU>,
  encode: (x0: PYU) => $json.Json$
): $json.Json$;

export function delta_to_json(delta: CrdtDelta$<string>): $json.Json$;

export function or_delta_from_json_with<QAI>(
  input: string,
  decoder: $decode.Decoder$<QAI>
): _.Result<ORMapDelta$<QAI>, $json.DecodeError$>;

export function delta_from_json_with<PYZ>(
  input: string,
  decoder: $decode.Decoder$<PYZ>
): _.Result<CrdtDelta$<PYZ>, $json.DecodeError$>;

export function delta_from_json(input: string): _.Result<
  CrdtDelta$<string>,
  $json.DecodeError$
>;

export function or_import_legacy<QAV>(
  input: string,
  spec: CrdtSpec$<QAV>,
  decoder: $decode.Decoder$<QAV>,
  replica: $replica_id.ReplicaId$
): _.Result<ORMap$<QAV>, $json.DecodeError$>;

export function lww_import_legacy(
  input: string,
  spec: CrdtSpec$<string>,
  replica: $replica_id.ReplicaId$
): _.Result<LWWMap$<string>, $json.DecodeError$>;
