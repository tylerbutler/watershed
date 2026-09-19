import type * as $set from "../../gleam_stdlib/gleam/set.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $replica_id from "../lattice_core/replica_id.d.mts";

export class Dot extends _.CustomType {
  /** @deprecated */
  constructor(replica_id: $replica_id.ReplicaId$, counter: number);
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  counter: number;
}
export function Dot$Dot(
  replica_id: $replica_id.ReplicaId$,
  counter: number,
): Dot$;
export function Dot$isDot(value: any): value is Dot$;
export function Dot$Dot$0(value: Dot$): $replica_id.ReplicaId$;
export function Dot$Dot$replica_id(value: Dot$): $replica_id.ReplicaId$;
export function Dot$Dot$1(value: Dot$): number;
export function Dot$Dot$counter(value: Dot$): number;

export type Dot$ = Dot;

declare class DotContext extends _.CustomType {
  /** @deprecated */
  constructor(dots: $set.Set$<Dot$>);
  /** @deprecated */
  dots: $set.Set$<Dot$>;
}

export type DotContext$ = DotContext;

export function new$(): DotContext$;

export function add_dot(
  context: DotContext$,
  replica_id: $replica_id.ReplicaId$,
  counter: number
): DotContext$;

export function remove_dots(context: DotContext$, dots: _.List<Dot$>): DotContext$;

export function contains_dots(context: DotContext$, dots: _.List<Dot$>): boolean;
