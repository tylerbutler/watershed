import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $g_counter from "../lattice_counters/g_counter.d.mts";

declare class PNCounter extends _.CustomType {
  /** @deprecated */
  constructor(positive: $g_counter.GCounter$, negative: $g_counter.GCounter$);
  /** @deprecated */
  positive: $g_counter.GCounter$;
  /** @deprecated */
  negative: $g_counter.GCounter$;
}

export type PNCounter$ = PNCounter;

export class NegativeDelta extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}
export function UpdateError$NegativeDelta($0: number): UpdateError$;
export function UpdateError$isNegativeDelta(value: any): value is UpdateError$;
export function UpdateError$NegativeDelta$0(value: UpdateError$): number;

export type UpdateError$ = NegativeDelta;

export function new$(replica_id: $replica_id.ReplicaId$): PNCounter$;

export function increment_with_delta(counter: PNCounter$, delta: number): _.Result<
  [PNCounter$, PNCounter$],
  UpdateError$
>;

export function increment(counter: PNCounter$, delta: number): _.Result<
  PNCounter$,
  UpdateError$
>;

export function decrement_with_delta(counter: PNCounter$, delta: number): _.Result<
  [PNCounter$, PNCounter$],
  UpdateError$
>;

export function decrement(counter: PNCounter$, delta: number): _.Result<
  PNCounter$,
  UpdateError$
>;

export function value(counter: PNCounter$): number;

export function merge(a: PNCounter$, b: PNCounter$): PNCounter$;

export function to_json(counter: PNCounter$): $json.Json$;

export function from_json(json_string: string): _.Result<
  PNCounter$,
  $json.DecodeError$
>;
