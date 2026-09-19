import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as _ from "../gleam.d.mts";

declare class LWWRegister<JUV> extends _.CustomType {
  /** @deprecated */
  constructor(value: JUV, timestamp: number, replica_id: $replica.ReplicaId$);
  /** @deprecated */
  value: JUV;
  /** @deprecated */
  timestamp: number;
  /** @deprecated */
  replica_id: $replica.ReplicaId$;
}

export type LWWRegister$<JUV> = LWWRegister<JUV>;

export function new$<JUW>(
  value: JUW,
  timestamp: number,
  replica_id: $replica.ReplicaId$
): LWWRegister$<JUW>;

export function set_with_delta<JVB>(
  register: LWWRegister$<JVB>,
  value: JVB,
  timestamp: number,
  replica_id: $replica.ReplicaId$
): [LWWRegister$<JVB>, LWWRegister$<JVB>];

export function set<JUY>(
  register: LWWRegister$<JUY>,
  value: JUY,
  timestamp: number,
  replica_id: $replica.ReplicaId$
): LWWRegister$<JUY>;

export function value<JVF>(register: LWWRegister$<JVF>): JVF;

export function timestamp(register: LWWRegister$<any>): number;

export function replica_id(register: LWWRegister$<any>): $replica.ReplicaId$;

export function merge<JVL>(a: LWWRegister$<JVL>, b: LWWRegister$<JVL>): LWWRegister$<
  JVL
>;

export function to_json_with<JVQ>(
  register: LWWRegister$<JVQ>,
  encode: (x0: JVQ) => $json.Json$
): $json.Json$;

export function to_json(register: LWWRegister$<string>): $json.Json$;

export function from_json_with<JVV>(
  json_string: string,
  decoder: $decode.Decoder$<JVV>
): _.Result<LWWRegister$<JVV>, $json.DecodeError$>;

export function from_json(json_string: string): _.Result<
  LWWRegister$<string>,
  $json.DecodeError$
>;
