import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $set from "../../gleam_stdlib/gleam/set.d.mts";
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

declare class ORSet<NRB> extends _.CustomType {
  /** @deprecated */
  constructor(
    replica_id: $replica_id.ReplicaId$,
    counter: number,
    entries: $dict.Dict$<NRB, $set.Set$<Tag$>>,
    tombstones: $set.Set$<Tag$>,
    pruned: $version_vector.VersionVector$
  );
  /** @deprecated */
  replica_id: $replica_id.ReplicaId$;
  /** @deprecated */
  counter: number;
  /** @deprecated */
  entries: $dict.Dict$<NRB, $set.Set$<Tag$>>;
  /** @deprecated */
  tombstones: $set.Set$<Tag$>;
  /** @deprecated */
  pruned: $version_vector.VersionVector$;
}

export type ORSet$<NRB> = ORSet<NRB>;

export class Diff<NRC> extends _.CustomType {
  /** @deprecated */
  constructor(added: $set.Set$<NRC>, removed: $set.Set$<NRC>);
  /** @deprecated */
  added: $set.Set$<NRC>;
  /** @deprecated */
  removed: $set.Set$<NRC>;
}
export function Diff$Diff<NRC>(
  added: $set.Set$<NRC>,
  removed: $set.Set$<NRC>,
): Diff$<NRC>;
export function Diff$isDiff<NRC>(value: any): value is Diff$<unknown>;
export function Diff$Diff$0<NRC>(value: Diff$<NRC>): $set.Set$<NRC>;
export function Diff$Diff$added<NRC>(value: Diff$<NRC>): $set.Set$<NRC>;
export function Diff$Diff$1<NRC>(value: Diff$<NRC>): $set.Set$<NRC>;
export function Diff$Diff$removed<NRC>(value: Diff$<NRC>): $set.Set$<NRC>;

export type Diff$<NRC> = Diff<NRC>;

export function new$(replica_id: $replica_id.ReplicaId$): ORSet$<any>;

export function add_with_delta<NRI>(orset: ORSet$<NRI>, element: NRI): [
  ORSet$<NRI>,
  ORSet$<NRI>
];

export function add<NRF>(orset: ORSet$<NRF>, element: NRF): ORSet$<NRF>;

export function remove_with_delta<NRP>(orset: ORSet$<NRP>, element: NRP): [
  ORSet$<NRP>,
  ORSet$<NRP>
];

export function remove<NRM>(orset: ORSet$<NRM>, element: NRM): ORSet$<NRM>;

export function remove_all<NRT>(orset: ORSet$<NRT>, elements: _.List<NRT>): ORSet$<
  NRT
>;

export function value<NSC>(orset: ORSet$<NSC>): $set.Set$<NSC>;

export function remove_where<NRX>(
  orset: ORSet$<NRX>,
  predicate: (x0: NRX) => boolean
): ORSet$<NRX>;

export function contains<NSA>(orset: ORSet$<NSA>, element: NSA): boolean;

export function diff<NSF>(before: ORSet$<NSF>, after: ORSet$<NSF>): Diff$<NSF>;

export function merge<NSJ>(a: ORSet$<NSJ>, b: ORSet$<NSJ>): ORSet$<NSJ>;

export function merge_with_diff<NSN>(local: ORSet$<NSN>, remote: ORSet$<NSN>): [
  ORSet$<NSN>,
  Diff$<NSN>
];

export function remove_with_bound<NSV>(orset: ORSet$<NSV>, element: NSV): [
  ORSet$<NSV>,
  $version_vector.VersionVector$
];

export function pruned_vv(orset: ORSet$<any>): $version_vector.VersionVector$;

export function prune<NTB>(
  orset: ORSet$<NTB>,
  stable_vv: $version_vector.VersionVector$
): ORSet$<NTB>;

export function to_json(orset: ORSet$<string>): $json.Json$;

export function to_json_with<NTF>(
  orset: ORSet$<NTF>,
  encode: (x0: NTF) => $json.Json$
): $json.Json$;

export function from_json(json_string: string): _.Result<
  ORSet$<string>,
  $json.DecodeError$
>;

export function from_json_with<NTM>(
  json_string: string,
  decoder: $decode.Decoder$<NTM>
): _.Result<ORSet$<NTM>, $json.DecodeError$>;
