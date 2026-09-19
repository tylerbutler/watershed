import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $version_vector from "../../lattice_core/lattice_core/version_vector.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $crdt from "../lattice_maps/crdt.d.mts";

export type ORMap = $crdt.ORMap$<any>;

export type ORMapDelta = $crdt.ORMapDelta$<any>;

export function new$<SWW>(
  replica: $replica_id.ReplicaId$,
  spec: $crdt.CrdtSpec$<SWW>
): $crdt.ORMap$<SWW>;

export function replica_id(map: $crdt.ORMap$<any>): $replica_id.ReplicaId$;

export function spec<SXB>(map: $crdt.ORMap$<SXB>): $crdt.CrdtSpec$<SXB>;

export function bind<SXE>(
  map: $crdt.ORMap$<SXE>,
  replica: $replica_id.ReplicaId$
): $crdt.ORMap$<SXE>;

export function get<SXH>(map: $crdt.ORMap$<SXH>, key: string): _.Result<
  $crdt.Crdt$<SXH>,
  undefined
>;

export function keys(map: $crdt.ORMap$<any>): _.List<string>;

export function values<SXP>(map: $crdt.ORMap$<SXP>): _.List<$crdt.Crdt$<SXP>>;

export function update_with_delta<SYA>(
  map: $crdt.ORMap$<SYA>,
  key: string,
  callback: (x0: $crdt.Crdt$<SYA>) => $crdt.Crdt$<SYA>
): _.Result<[$crdt.ORMap$<SYA>, $crdt.ORMapDelta$<SYA>], $crdt.MergeError$>;

export function update<SXT>(
  map: $crdt.ORMap$<SXT>,
  key: string,
  callback: (x0: $crdt.Crdt$<SXT>) => $crdt.Crdt$<SXT>
): _.Result<$crdt.ORMap$<SXT>, $crdt.MergeError$>;

export function update_delta<SYI, SYM>(
  map: $crdt.ORMap$<SYI>,
  key: string,
  callback: (x0: $crdt.Crdt$<SYI>, x1: $crdt.EditContext$) => _.Result<
    $crdt.CrdtDelta$<SYI>,
    SYM
  >
): _.Result<
  [$crdt.ORMap$<SYI>, $crdt.ORMapDelta$<SYI>],
  $crdt.UpdateError$<SYM>
>;

export function remove_with_delta<SYX>(map: $crdt.ORMap$<SYX>, key: string): [
  $crdt.ORMap$<SYX>,
  $crdt.ORMapDelta$<SYX>
];

export function remove<SYU>(map: $crdt.ORMap$<SYU>, key: string): $crdt.ORMap$<
  SYU
>;

export function merge_as<SZH>(
  a: $crdt.ORMap$<SZH>,
  b: $crdt.ORMap$<SZH>,
  replica: $replica_id.ReplicaId$
): _.Result<$crdt.ORMap$<SZH>, $crdt.MergeError$>;

export function merge<SZB>(a: $crdt.ORMap$<SZB>, b: $crdt.ORMap$<SZB>): _.Result<
  $crdt.ORMap$<SZB>,
  $crdt.MergeError$
>;

export function empty_delta<SZN>(map: $crdt.ORMap$<SZN>): $crdt.ORMapDelta$<SZN>;

export function apply_delta<SZQ>(
  map: $crdt.ORMap$<SZQ>,
  delta: $crdt.ORMapDelta$<SZQ>
): _.Result<$crdt.ORMap$<SZQ>, $crdt.MergeError$>;

export function merge_deltas<SZW>(
  a: $crdt.ORMapDelta$<SZW>,
  b: $crdt.ORMapDelta$<SZW>
): _.Result<$crdt.ORMapDelta$<SZW>, $crdt.MergeError$>;

export function prune<TAC>(
  map: $crdt.ORMap$<TAC>,
  stable: $version_vector.VersionVector$
): $crdt.ORMap$<TAC>;

export function internal_value_count(map: $crdt.ORMap$<any>): number;

export function to_json(map: $crdt.ORMap$<string>): $json.Json$;

export function to_json_with<TAI>(
  map: $crdt.ORMap$<TAI>,
  encode: (x0: TAI) => $json.Json$
): $json.Json$;

export function from_json_with<TAN>(
  input: string,
  decoder: $decode.Decoder$<TAN>
): _.Result<$crdt.ORMap$<TAN>, $json.DecodeError$>;

export function from_json(input: string): _.Result<
  $crdt.ORMap$<string>,
  $json.DecodeError$
>;

export function delta_to_json_with<TAT>(
  delta: $crdt.ORMapDelta$<TAT>,
  encode: (x0: TAT) => $json.Json$
): $json.Json$;

export function delta_to_json(delta: $crdt.ORMapDelta$<string>): $json.Json$;

export function delta_from_json_with<TAY>(
  input: string,
  decoder: $decode.Decoder$<TAY>
): _.Result<$crdt.ORMapDelta$<TAY>, $json.DecodeError$>;

export function delta_from_json(input: string): _.Result<
  $crdt.ORMapDelta$<string>,
  $json.DecodeError$
>;

export function import_legacy<TBD>(
  input: string,
  spec: $crdt.CrdtSpec$<TBD>,
  decoder: $decode.Decoder$<TBD>,
  replica: $replica_id.ReplicaId$
): _.Result<$crdt.ORMap$<TBD>, $json.DecodeError$>;
