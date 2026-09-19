import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $crdt from "../lattice_maps/crdt.d.mts";

export type LWWMap = $crdt.LWWMap$<any>;

export function new$<SSV>(
  replica: $replica_id.ReplicaId$,
  spec: $crdt.CrdtSpec$<SSV>
): $crdt.LWWMap$<SSV>;

export function replica_id(map: $crdt.LWWMap$<any>): $replica_id.ReplicaId$;

export function spec<STA>(map: $crdt.LWWMap$<STA>): $crdt.CrdtSpec$<STA>;

export function bind<STD>(
  map: $crdt.LWWMap$<STD>,
  replica: $replica_id.ReplicaId$
): $crdt.LWWMap$<STD>;

export function get<STG>(map: $crdt.LWWMap$<STG>, key: string): _.Result<
  $crdt.Crdt$<STG>,
  undefined
>;

export function set<STL>(
  map: $crdt.LWWMap$<STL>,
  key: string,
  value: $crdt.Crdt$<STL>,
  timestamp: number
): _.Result<$crdt.LWWMap$<STL>, $crdt.MergeError$>;

export function update<STR, STV>(
  map: $crdt.LWWMap$<STR>,
  key: string,
  timestamp: number,
  callback: (x0: $crdt.Crdt$<STR>, x1: $crdt.EditContext$) => _.Result<
    $crdt.Crdt$<STR>,
    STV
  >
): _.Result<$crdt.LWWMap$<STR>, $crdt.UpdateError$<STV>>;

export function remove<SUC>(
  map: $crdt.LWWMap$<SUC>,
  key: string,
  timestamp: number
): _.Result<$crdt.LWWMap$<SUC>, $crdt.MergeError$>;

export function keys(map: $crdt.LWWMap$<any>): _.List<string>;

export function values<SUK>(map: $crdt.LWWMap$<SUK>): _.List<$crdt.Crdt$<SUK>>;

export function tombstone_count(map: $crdt.LWWMap$<any>): number;

export function pruned_timestamp(map: $crdt.LWWMap$<any>): number;

export function prune<SUS>(map: $crdt.LWWMap$<SUS>, stable: number): $crdt.LWWMap$<
  SUS
>;

export function merge_as<SVB>(
  a: $crdt.LWWMap$<SVB>,
  b: $crdt.LWWMap$<SVB>,
  replica: $replica_id.ReplicaId$
): _.Result<$crdt.LWWMap$<SVB>, $crdt.MergeError$>;

export function merge<SUV>(a: $crdt.LWWMap$<SUV>, b: $crdt.LWWMap$<SUV>): _.Result<
  $crdt.LWWMap$<SUV>,
  $crdt.MergeError$
>;

export function to_json_with<SVI>(
  map: $crdt.LWWMap$<SVI>,
  encode: (x0: SVI) => $json.Json$
): $json.Json$;

export function to_json(map: $crdt.LWWMap$<string>): $json.Json$;

export function from_json_with<SVN>(
  input: string,
  decoder: $decode.Decoder$<SVN>
): _.Result<$crdt.LWWMap$<SVN>, $json.DecodeError$>;

export function from_json(input: string): _.Result<
  $crdt.LWWMap$<string>,
  $json.DecodeError$
>;

export function import_legacy(
  input: string,
  spec: $crdt.CrdtSpec$<string>,
  replica: $replica_id.ReplicaId$
): _.Result<$crdt.LWWMap$<string>, $json.DecodeError$>;
