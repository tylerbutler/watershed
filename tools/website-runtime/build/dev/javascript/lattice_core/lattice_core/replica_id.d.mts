import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $order from "../../gleam_stdlib/gleam/order.d.mts";
import type * as _ from "../gleam.d.mts";

declare class ReplicaId extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}

export type ReplicaId$ = ReplicaId;

export function new$(id: string): ReplicaId$;

export function to_string(replica_id: ReplicaId$): string;

export function compare(a: ReplicaId$, b: ReplicaId$): $order.Order$;

export function to_json(replica_id: ReplicaId$): $json.Json$;

export function decoder(): $decode.Decoder$<ReplicaId$>;
