import type * as $dict from "../../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../../gleam_stdlib/gleam/option.d.mts";
import type * as $replica_id from "../../../lattice_core/lattice_core/replica_id.d.mts";
import type * as _ from "../../gleam.d.mts";

export class Modern extends _.CustomType {
  /** @deprecated */
  constructor(writer: $replica_id.ReplicaId$);
  /** @deprecated */
  writer: $replica_id.ReplicaId$;
}
export function Provenance$Modern(writer: $replica_id.ReplicaId$): Provenance$;
export function Provenance$isModern(value: any): value is Provenance$;
export function Provenance$Modern$0(value: Provenance$): $replica_id.ReplicaId$;
export function Provenance$Modern$writer(value: Provenance$): $replica_id.ReplicaId$;

export class Legacy extends _.CustomType {
  /** @deprecated */
  constructor(tie_key: string);
  /** @deprecated */
  tie_key: string;
}
export function Provenance$Legacy(tie_key: string): Provenance$;
export function Provenance$isLegacy(value: any): value is Provenance$;
export function Provenance$Legacy$0(value: Provenance$): string;
export function Provenance$Legacy$tie_key(value: Provenance$): string;

export type Provenance$ = Modern | Legacy;

export class Entry<OYF> extends _.CustomType {
  /** @deprecated */
  constructor(
    value: $option.Option$<OYF>,
    timestamp: number,
    provenance: Provenance$
  );
  /** @deprecated */
  value: $option.Option$<OYF>;
  /** @deprecated */
  timestamp: number;
  /** @deprecated */
  provenance: Provenance$;
}
export function Entry$Entry<OYF>(
  value: $option.Option$<OYF>,
  timestamp: number,
  provenance: Provenance$,
): Entry$<OYF>;
export function Entry$isEntry<OYF>(value: any): value is Entry$<unknown>;
export function Entry$Entry$0<OYF>(value: Entry$<OYF>): $option.Option$<OYF>;
export function Entry$Entry$value<OYF>(value: Entry$<OYF>): $option.Option$<OYF>;
export function Entry$Entry$1<OYF>(
  value: Entry$<OYF>,
): number;
export function Entry$Entry$timestamp<OYF>(value: Entry$<OYF>): number;
export function Entry$Entry$2<OYF>(value: Entry$<OYF>): Provenance$;
export function Entry$Entry$provenance<OYF>(value: Entry$<OYF>): Provenance$;

export type Entry$<OYF> = Entry<OYF>;

export class State<OYG> extends _.CustomType {
  /** @deprecated */
  constructor(
    entries: $dict.Dict$<string, Entry$<OYG>>,
    pruned_timestamp: number
  );
  /** @deprecated */
  entries: $dict.Dict$<string, Entry$<OYG>>;
  /** @deprecated */
  pruned_timestamp: number;
}
export function State$State<OYG>(
  entries: $dict.Dict$<string, Entry$<OYG>>,
  pruned_timestamp: number,
): State$<OYG>;
export function State$isState<OYG>(value: any): value is State$<unknown>;
export function State$State$0<OYG>(value: State$<OYG>): $dict.Dict$<
  string,
  Entry$<OYG>
>;
export function State$State$entries<OYG>(value: State$<OYG>): $dict.Dict$<
  string,
  Entry$<OYG>
>;
export function State$State$1<OYG>(value: State$<OYG>): number;
export function State$State$pruned_timestamp<OYG>(value: State$<OYG>): number;

export type State$<OYG> = State<OYG>;

export class TimestampNotAdvanced extends _.CustomType {
  /** @deprecated */
  constructor(key: string, timestamp: number, floor: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  timestamp: number;
  /** @deprecated */
  floor: number;
}
export function Error$TimestampNotAdvanced(
  key: string,
  timestamp: number,
  floor: number,
): Error$;
export function Error$isTimestampNotAdvanced(value: any): value is Error$;
export function Error$TimestampNotAdvanced$0(value: Error$): string;
export function Error$TimestampNotAdvanced$key(value: Error$): string;
export function Error$TimestampNotAdvanced$1(value: Error$): number;
export function Error$TimestampNotAdvanced$timestamp(value: Error$): number;
export function Error$TimestampNotAdvanced$2(value: Error$): number;
export function Error$TimestampNotAdvanced$floor(value: Error$): number;

export class ConflictingWrite extends _.CustomType {
  /** @deprecated */
  constructor(key: string, timestamp: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  timestamp: number;
}
export function Error$ConflictingWrite(key: string, timestamp: number): Error$;
export function Error$isConflictingWrite(value: any): value is Error$;
export function Error$ConflictingWrite$0(value: Error$): string;
export function Error$ConflictingWrite$key(value: Error$): string;
export function Error$ConflictingWrite$1(value: Error$): number;
export function Error$ConflictingWrite$timestamp(value: Error$): number;

export class InvalidTimestamp extends _.CustomType {
  /** @deprecated */
  constructor(key: string, timestamp: number);
  /** @deprecated */
  key: string;
  /** @deprecated */
  timestamp: number;
}
export function Error$InvalidTimestamp(key: string, timestamp: number): Error$;
export function Error$isInvalidTimestamp(value: any): value is Error$;
export function Error$InvalidTimestamp$0(value: Error$): string;
export function Error$InvalidTimestamp$key(value: Error$): string;
export function Error$InvalidTimestamp$1(value: Error$): number;
export function Error$InvalidTimestamp$timestamp(value: Error$): number;

export type Error$ = TimestampNotAdvanced | ConflictingWrite | InvalidTimestamp;

export function Error$key(value: Error$): string;
export function Error$timestamp(value: Error$): number;

export function new$(): State$<any>;

export function check_timestamp(
  state: State$<any>,
  key: string,
  timestamp: number
): _.Result<undefined, Error$>;

export function put<OYN>(
  state: State$<OYN>,
  key: string,
  entry: Entry$<OYN>,
  equal: (x0: OYN, x1: OYN) => boolean
): _.Result<State$<OYN>, Error$>;

export function prune<OZP>(state: State$<OZP>, stable: number): State$<OZP>;

export function merge<OZJ>(
  a: State$<OZJ>,
  b: State$<OZJ>,
  equal: (x0: OZJ, x1: OZJ) => boolean
): _.Result<State$<OZJ>, Error$>;
