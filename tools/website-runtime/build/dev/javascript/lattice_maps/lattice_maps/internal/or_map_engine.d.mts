import type * as $dict from "../../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../../gleam_stdlib/gleam/option.d.mts";
import type * as $order from "../../../gleam_stdlib/gleam/order.d.mts";
import type * as $replica_id from "../../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $version_vector from "../../../lattice_core/lattice_core/version_vector.d.mts";
import type * as $or_set from "../../../lattice_sets/lattice_sets/or_set.d.mts";
import type * as _ from "../../gleam.d.mts";

export class Initial extends _.CustomType {}
export function Generation$Initial(): Generation$;
export function Generation$isInitial(value: any): value is Generation$;

export class Generation extends _.CustomType {
  /** @deprecated */
  constructor(clock: number, creator: $replica_id.ReplicaId$);
  /** @deprecated */
  clock: number;
  /** @deprecated */
  creator: $replica_id.ReplicaId$;
}
export function Generation$Generation(
  clock: number,
  creator: $replica_id.ReplicaId$,
): Generation$;
export function Generation$isGeneration(value: any): value is Generation$;
export function Generation$Generation$0(value: Generation$): number;
export function Generation$Generation$clock(value: Generation$): number;
export function Generation$Generation$1(value: Generation$): $replica_id.ReplicaId$;
export function Generation$Generation$creator(
  value: Generation$,
): $replica_id.ReplicaId$;

export type Generation$ = Initial | Generation;

export class Entry<PHE> extends _.CustomType {
  /** @deprecated */
  constructor(
    generation: Generation$,
    membership: $or_set.ORSet$<string>,
    value: $option.Option$<PHE>
  );
  /** @deprecated */
  generation: Generation$;
  /** @deprecated */
  membership: $or_set.ORSet$<string>;
  /** @deprecated */
  value: $option.Option$<PHE>;
}
export function Entry$Entry<PHE>(
  generation: Generation$,
  membership: $or_set.ORSet$<string>,
  value: $option.Option$<PHE>,
): Entry$<PHE>;
export function Entry$isEntry<PHE>(value: any): value is Entry$<unknown>;
export function Entry$Entry$0<PHE>(value: Entry$<PHE>): Generation$;
export function Entry$Entry$generation<PHE>(value: Entry$<PHE>): Generation$;
export function Entry$Entry$1<PHE>(value: Entry$<PHE>): $or_set.ORSet$<string>;
export function Entry$Entry$membership<PHE>(value: Entry$<PHE>): $or_set.ORSet$<
  string
>;
export function Entry$Entry$2<PHE>(value: Entry$<PHE>): $option.Option$<PHE>;
export function Entry$Entry$value<PHE>(value: Entry$<PHE>): $option.Option$<PHE>;

export type Entry$<PHE> = Entry<PHE>;

export class State<PHF> extends _.CustomType {
  /** @deprecated */
  constructor(clock: number, entries: $dict.Dict$<string, Entry$<PHF>>);
  /** @deprecated */
  clock: number;
  /** @deprecated */
  entries: $dict.Dict$<string, Entry$<PHF>>;
}
export function State$State<PHF>(
  clock: number,
  entries: $dict.Dict$<string, Entry$<PHF>>,
): State$<PHF>;
export function State$isState<PHF>(value: any): value is State$<unknown>;
export function State$State$0<PHF>(value: State$<PHF>): number;
export function State$State$clock<PHF>(value: State$<PHF>): number;
export function State$State$1<PHF>(value: State$<PHF>): $dict.Dict$<
  string,
  Entry$<PHF>
>;
export function State$State$entries<PHF>(value: State$<PHF>): $dict.Dict$<
  string,
  Entry$<PHF>
>;

export type State$<PHF> = State<PHF>;

export function new$(): State$<any>;

export function compare(a: Generation$, b: Generation$): $order.Order$;

export function clock(generation: Generation$): number;

export function active(entry: Entry$<any>, key: string): boolean;

export function prepare<PHK>(
  state: State$<PHK>,
  key: string,
  writer: $replica_id.ReplicaId$
): Entry$<PHK>;

export function singleton<PHN>(
  key: string,
  entry: Entry$<PHN>,
  high_water: number
): State$<PHN>;

export function remove<PHQ>(state: State$<PHQ>, key: string): [
  State$<PHQ>,
  State$<any>
];

export function join<PHV, PHX, PIB, PID>(
  a: State$<PHV>,
  b: State$<PHX>,
  combine: (
    x0: string,
    x1: Generation$,
    x2: $option.Option$<PHV>,
    x3: $option.Option$<PHX>
  ) => _.Result<$option.Option$<PIB>, PID>
): _.Result<State$<PIB>, PID>;

export function prune<PIJ>(
  state: State$<PIJ>,
  stable: $version_vector.VersionVector$
): State$<PIJ>;
