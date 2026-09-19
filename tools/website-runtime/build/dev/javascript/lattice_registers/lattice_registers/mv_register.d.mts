import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $version_vector from "../../lattice_core/lattice_core/version_vector.d.mts";
import type * as _ from "../gleam.d.mts";

declare class Tag extends _.CustomType {
  /** @deprecated */
  constructor(replica_id: $replica_id.ReplicaId$, counter: number);
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  counter: number;
}

export type Tag$ = Tag;

declare class MVRegister<JZJ> extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    entries: $dict.Dict$<Tag$, JZJ>,
    vclock: $version_vector.VersionVector$
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  entries: $dict.Dict$<Tag$, JZJ>;
  /** @deprecated */
  vclock: $version_vector.VersionVector$;
}

export type MVRegister$<JZJ> = MVRegister<JZJ>;

export function new$(replica_id: $replica_id.ReplicaId$): MVRegister$<any>;

export function set_with_delta<JZP>(register: MVRegister$<JZP>, val: JZP): [
  MVRegister$<JZP>,
  MVRegister$<JZP>
];

export function set<JZM>(register: MVRegister$<JZM>, val: JZM): MVRegister$<JZM>;

export function value<JZT>(register: MVRegister$<JZT>): _.List<JZT>;

export function merge<JZW>(a: MVRegister$<JZW>, b: MVRegister$<JZW>): MVRegister$<
  JZW
>;

export function to_json_with<KAB>(
  register: MVRegister$<KAB>,
  encode: (x0: KAB) => $json.Json$
): $json.Json$;

export function to_json(register: MVRegister$<string>): $json.Json$;

export function from_json_with<KAG>(
  json_string: string,
  decoder: $decode.Decoder$<KAG>
): _.Result<MVRegister$<KAG>, $json.DecodeError$>;

export function from_json(json_string: string): _.Result<
  MVRegister$<string>,
  $json.DecodeError$
>;
