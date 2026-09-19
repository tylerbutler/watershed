import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $replica_id from "../lattice_core/replica_id.d.mts";

export class Before extends _.CustomType {}
export function Order$Before(): Order$;
export function Order$isBefore(value: any): value is Order$;

export class After extends _.CustomType {}
export function Order$After(): Order$;
export function Order$isAfter(value: any): value is Order$;

export class Concurrent extends _.CustomType {}
export function Order$Concurrent(): Order$;
export function Order$isConcurrent(value: any): value is Order$;

export class Equal extends _.CustomType {}
export function Order$Equal(): Order$;
export function Order$isEqual(value: any): value is Order$;

export type Order$ = Before | After | Concurrent | Equal;

declare class VersionVector extends _.CustomType {
  /** @deprecated */
  constructor(dict: $dict.Dict$<$replica_id.ReplicaId$, number>);
  /** @deprecated */
  dict: $dict.Dict$<$replica_id.ReplicaId$, number>;
}

export type VersionVector$ = VersionVector;

export function new$(): VersionVector$;

export function increment(
  vector: VersionVector$,
  replica_id: $replica_id.ReplicaId$
): VersionVector$;

export function get(vector: VersionVector$, replica_id: $replica_id.ReplicaId$): number;

export function compare(a: VersionVector$, b: VersionVector$): Order$;

export function dominates(a: VersionVector$, b: VersionVector$): boolean;

export function is_empty(vector: VersionVector$): boolean;

export function set_max(
  vv: VersionVector$,
  replica_id: $replica_id.ReplicaId$,
  value: number
): VersionVector$;

export function merge(a: VersionVector$, b: VersionVector$): VersionVector$;

export function to_json(vector: VersionVector$): $json.Json$;

export function from_json(json_string: string): _.Result<
  VersionVector$,
  $json.DecodeError$
>;

export function decoder(): $decode.Decoder$<VersionVector$>;

export function to_dict(vector: VersionVector$): $dict.Dict$<
  $replica_id.ReplicaId$,
  number
>;

export function from_dict(clocks: $dict.Dict$<$replica_id.ReplicaId$, number>): VersionVector$;
