import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../lattice_core/lattice_core/replica_id.d.mts";
import type * as $crdt from "../../lattice_maps/lattice_maps/crdt.d.mts";
import type * as $or_set from "../../lattice_sets/lattice_sets/or_set.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $json_ot from "../watershed/json_ot.d.mts";

export class Clocks extends _.CustomType {
  /** @deprecated */
  constructor(key_counter: number, member_counters: $dict.Dict$<string, number>);
  /** @deprecated */
  key_counter: number;
  /** @deprecated */
  member_counters: $dict.Dict$<string, number>;
}
export function Clocks$Clocks(
  key_counter: number,
  member_counters: $dict.Dict$<string, number>,
): Clocks$;
export function Clocks$isClocks(value: any): value is Clocks$;
export function Clocks$Clocks$0(value: Clocks$): number;
export function Clocks$Clocks$key_counter(value: Clocks$): number;
export function Clocks$Clocks$1(value: Clocks$): $dict.Dict$<string, number>;
export function Clocks$Clocks$member_counters(value: Clocks$): $dict.Dict$<
  string,
  number
>;

export type Clocks$ = Clocks;

export class AddMember extends _.CustomType {
  /** @deprecated */
  constructor(member: string);
  /** @deprecated */
  member: string;
}
export function Intent$AddMember(member: string): Intent$;
export function Intent$isAddMember(value: any): value is Intent$;
export function Intent$AddMember$0(value: Intent$): string;
export function Intent$AddMember$member(value: Intent$): string;

export class RemoveMember extends _.CustomType {
  /** @deprecated */
  constructor(member: string);
  /** @deprecated */
  member: string;
}
export function Intent$RemoveMember(member: string): Intent$;
export function Intent$isRemoveMember(value: any): value is Intent$;
export function Intent$RemoveMember$0(value: Intent$): string;
export function Intent$RemoveMember$member(value: Intent$): string;

export class RemoveKey extends _.CustomType {}
export function Intent$RemoveKey(): Intent$;
export function Intent$isRemoveKey(value: any): value is Intent$;

export type Intent$ = AddMember | RemoveMember | RemoveKey;

export class InvalidState extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function LeafError$InvalidState(detail: string): LeafError$;
export function LeafError$isInvalidState(value: any): value is LeafError$;
export function LeafError$InvalidState$0(value: LeafError$): string;
export function LeafError$InvalidState$detail(value: LeafError$): string;

export class CounterExhausted extends _.CustomType {
  /** @deprecated */
  constructor(detail: string);
  /** @deprecated */
  detail: string;
}
export function LeafError$CounterExhausted(detail: string): LeafError$;
export function LeafError$isCounterExhausted(value: any): value is LeafError$;
export function LeafError$CounterExhausted$0(value: LeafError$): string;
export function LeafError$CounterExhausted$detail(value: LeafError$): string;

export type LeafError$ = InvalidState | CounterExhausted;

export function LeafError$detail(value: LeafError$): string;

declare class Snapshot extends _.CustomType {
  /** @deprecated */
  constructor(
    author: string,
    spec: string,
    clock: number,
    entries: _.List<Entry$>
  );
  /** @deprecated */
  author: string;
  /** @deprecated */
  spec: string;
  /** @deprecated */
  clock: number;
  /** @deprecated */
  entries: _.List<Entry$>;
}

type Snapshot$ = Snapshot;

declare class Entry extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    generation: $json_ot.JsonValue$,
    membership: string,
    value: $option.Option$<string>
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  generation: $json_ot.JsonValue$;
  /** @deprecated */
  membership: string;
  /** @deprecated */
  value: $option.Option$<string>;
}

type Entry$ = Entry;

declare class VectorMetadata extends _.CustomType {
  /** @deprecated */
  constructor(
    type_tag: string,
    version: number,
    clocks: $dict.Dict$<string, number>
  );
  /** @deprecated */
  type_tag: string;
  /** @deprecated */
  version: number;
  /** @deprecated */
  clocks: $dict.Dict$<string, number>;
}

type VectorMetadata$ = VectorMetadata;

declare class SetMetadata extends _.CustomType {
  /** @deprecated */
  constructor(
    native: $or_set.ORSet$<string>,
    counter: number,
    entries: $dict.Dict$<string, _.List<[string, number]>>,
    tombstones: _.List<[string, number]>
  );
  /** @deprecated */
  native: $or_set.ORSet$<string>;
  /** @deprecated */
  counter: number;
  /** @deprecated */
  entries: $dict.Dict$<string, _.List<[string, number]>>;
  /** @deprecated */
  tombstones: _.List<[string, number]>;
}

type SetMetadata$ = SetMetadata;

declare class MapMetadata extends _.CustomType {
  /** @deprecated */
  constructor(
    counter: number,
    key_entries: $dict.Dict$<string, _.List<[string, number]>>,
    key_tombstones: _.List<[string, number]>,
    mentioned_keys: _.List<string>,
    values: $dict.Dict$<string, SetMetadata$>,
    bounds: $dict.Dict$<string, VectorMetadata$>
  );
  /** @deprecated */
  counter: number;
  /** @deprecated */
  key_entries: $dict.Dict$<string, _.List<[string, number]>>;
  /** @deprecated */
  key_tombstones: _.List<[string, number]>;
  /** @deprecated */
  mentioned_keys: _.List<string>;
  /** @deprecated */
  values: $dict.Dict$<string, SetMetadata$>;
  /** @deprecated */
  bounds: $dict.Dict$<string, VectorMetadata$>;
}

type MapMetadata$ = MapMetadata;

export function merge(left: $crdt.ORMap$<string>, right: $crdt.ORMap$<string>): _.Result<
  $crdt.ORMap$<string>,
  LeafError$
>;

export function apply_delta(
  map: $crdt.ORMap$<string>,
  delta: $crdt.ORMapDelta$<string>
): _.Result<$crdt.ORMap$<string>, LeafError$>;

export function observe_state(clocks: Clocks$, map: $crdt.ORMap$<string>): _.Result<
  Clocks$,
  LeafError$
>;

export function retain_counter_floor(
  map: $crdt.ORMap$<string>,
  clocks: Clocks$,
  replica: $replica_id.ReplicaId$
): _.Result<$crdt.ORMap$<string>, LeafError$>;

export function new_clocks(): Clocks$;

export function decode_state(encoded: string): _.Result<
  $crdt.ORMap$<string>,
  LeafError$
>;

export function decode_delta(encoded: string): _.Result<
  $crdt.ORMapDelta$<string>,
  LeafError$
>;

export function validate_state(map: $crdt.ORMap$<string>): _.Result<
  undefined,
  LeafError$
>;

export function validate_intent(
  delta: $crdt.ORMapDelta$<string>,
  key: string,
  intent: Intent$
): _.Result<undefined, LeafError$>;

export function observe_delta(clocks: Clocks$, delta: $crdt.ORMapDelta$<string>): _.Result<
  Clocks$,
  LeafError$
>;

export function add(
  map: $crdt.ORMap$<string>,
  clocks: Clocks$,
  replica: $replica_id.ReplicaId$,
  key: string,
  member: string
): _.Result<[$crdt.ORMapDelta$<string>, Clocks$], LeafError$>;

export function remove_member(
  map: $crdt.ORMap$<string>,
  clocks: Clocks$,
  replica: $replica_id.ReplicaId$,
  key: string,
  member: string
): _.Result<[$crdt.ORMapDelta$<string>, Clocks$], LeafError$>;

export function remove_key(
  map: $crdt.ORMap$<string>,
  clocks: Clocks$,
  replica: $replica_id.ReplicaId$,
  key: string
): _.Result<[$crdt.ORMapDelta$<string>, Clocks$], LeafError$>;
