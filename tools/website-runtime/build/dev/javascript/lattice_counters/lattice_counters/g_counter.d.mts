import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as _ from "../gleam.d.mts";

declare class GCounter extends _.CustomType {
  /** @deprecated */
  constructor(
    dict: $dict.Dict$<$replica_id.ReplicaId$, number>,
    self_id: $replica_id.ReplicaId$
  );
  /** @deprecated */
  dict: $dict.Dict$<$replica_id.ReplicaId$, number>;
  /** @deprecated */
  self_id: $replica_id.ReplicaId$;
}

export type GCounter$ = GCounter;

export class NegativeDelta extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}
export function IncrementError$NegativeDelta($0: number): IncrementError$;
export function IncrementError$isNegativeDelta(
  value: any,
): value is IncrementError$;
export function IncrementError$NegativeDelta$0(value: IncrementError$): number;

export type IncrementError$ = NegativeDelta;

export function new$(replica_id: $replica_id.ReplicaId$): GCounter$;

export function increment_with_delta(counter: GCounter$, delta: number): _.Result<
  [GCounter$, GCounter$],
  IncrementError$
>;

export function increment(counter: GCounter$, delta: number): _.Result<
  GCounter$,
  IncrementError$
>;

export function value(counter: GCounter$): number;

export function merge(a: GCounter$, b: GCounter$): GCounter$;

export function to_json(counter: GCounter$): $json.Json$;

export function from_json(json_string: string): _.Result<
  GCounter$,
  $json.DecodeError$
>;

export function to_parts(counter: GCounter$): [
  $dict.Dict$<$replica_id.ReplicaId$, number>,
  $replica_id.ReplicaId$
];

export function from_parts(
  dict: $dict.Dict$<$replica_id.ReplicaId$, number>,
  self_id: $replica_id.ReplicaId$
): GCounter$;
