import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class MapState extends _.CustomType {
  /** @deprecated */
  constructor(
    sequenced: $dict.Dict$<string, $json.Json$>,
    insertion_order: _.List<string>,
    pending: _.List<PendingEntry$>
  );
  /** @deprecated */
  sequenced: $dict.Dict$<string, $json.Json$>;
  /** @deprecated */
  insertion_order: _.List<string>;
  /** @deprecated */
  pending: _.List<PendingEntry$>;
}
export function MapState$MapState(
  sequenced: $dict.Dict$<string, $json.Json$>,
  insertion_order: _.List<string>,
  pending: _.List<PendingEntry$>,
): MapState$;
export function MapState$isMapState(value: any): value is MapState$;
export function MapState$MapState$0(value: MapState$): $dict.Dict$<
  string,
  $json.Json$
>;
export function MapState$MapState$sequenced(value: MapState$): $dict.Dict$<
  string,
  $json.Json$
>;
export function MapState$MapState$1(value: MapState$): _.List<string>;
export function MapState$MapState$insertion_order(value: MapState$): _.List<
  string
>;
export function MapState$MapState$2(value: MapState$): _.List<PendingEntry$>;
export function MapState$MapState$pending(value: MapState$): _.List<
  PendingEntry$
>;

export type MapState$ = MapState;

export class PendingLifetime extends _.CustomType {
  /** @deprecated */
  constructor(key: string, sets: _.List<$json.Json$>);
  /** @deprecated */
  key: string;
  /** @deprecated */
  sets: _.List<$json.Json$>;
}
export function PendingEntry$PendingLifetime(
  key: string,
  sets: _.List<$json.Json$>,
): PendingEntry$;
export function PendingEntry$isPendingLifetime(
  value: any,
): value is PendingEntry$;
export function PendingEntry$PendingLifetime$0(value: PendingEntry$): string;
export function PendingEntry$PendingLifetime$key(value: PendingEntry$): string;
export function PendingEntry$PendingLifetime$1(value: PendingEntry$): _.List<
  $json.Json$
>;
export function PendingEntry$PendingLifetime$sets(value: PendingEntry$): _.List<
  $json.Json$
>;

export class PendingDelete extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function PendingEntry$PendingDelete(key: string): PendingEntry$;
export function PendingEntry$isPendingDelete(
  value: any,
): value is PendingEntry$;
export function PendingEntry$PendingDelete$0(value: PendingEntry$): string;
export function PendingEntry$PendingDelete$key(value: PendingEntry$): string;

export class PendingClear extends _.CustomType {}
export function PendingEntry$PendingClear(): PendingEntry$;
export function PendingEntry$isPendingClear(value: any): value is PendingEntry$;

export type PendingEntry$ = PendingLifetime | PendingDelete | PendingClear;

export class Set extends _.CustomType {
  /** @deprecated */
  constructor(key: string, value: $json.Json$);
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $json.Json$;
}
export function MapOperation$Set(
  key: string,
  value: $json.Json$,
): MapOperation$;
export function MapOperation$isSet(value: any): value is MapOperation$;
export function MapOperation$Set$0(value: MapOperation$): string;
export function MapOperation$Set$key(value: MapOperation$): string;
export function MapOperation$Set$1(value: MapOperation$): $json.Json$;
export function MapOperation$Set$value(value: MapOperation$): $json.Json$;

export class Delete extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function MapOperation$Delete(key: string): MapOperation$;
export function MapOperation$isDelete(value: any): value is MapOperation$;
export function MapOperation$Delete$0(value: MapOperation$): string;
export function MapOperation$Delete$key(value: MapOperation$): string;

export class Clear extends _.CustomType {}
export function MapOperation$Clear(): MapOperation$;
export function MapOperation$isClear(value: any): value is MapOperation$;

export type MapOperation$ = Set | Delete | Clear;

export class ValueChanged extends _.CustomType {
  /** @deprecated */
  constructor(
    key: string,
    previous_value: $option.Option$<$json.Json$>,
    value: $option.Option$<$json.Json$>,
    local: boolean
  );
  /** @deprecated */
  key: string;
  /** @deprecated */
  previous_value: $option.Option$<$json.Json$>;
  /** @deprecated */
  value: $option.Option$<$json.Json$>;
  /** @deprecated */
  local: boolean;
}
export function MapEvent$ValueChanged(
  key: string,
  previous_value: $option.Option$<$json.Json$>,
  value: $option.Option$<$json.Json$>,
  local: boolean,
): MapEvent$;
export function MapEvent$isValueChanged(value: any): value is MapEvent$;
export function MapEvent$ValueChanged$0(value: MapEvent$): string;
export function MapEvent$ValueChanged$key(value: MapEvent$): string;
export function MapEvent$ValueChanged$1(value: MapEvent$): $option.Option$<
  $json.Json$
>;
export function MapEvent$ValueChanged$previous_value(value: MapEvent$): $option.Option$<
  $json.Json$
>;
export function MapEvent$ValueChanged$2(value: MapEvent$): $option.Option$<
  $json.Json$
>;
export function MapEvent$ValueChanged$value(value: MapEvent$): $option.Option$<
  $json.Json$
>;
export function MapEvent$ValueChanged$3(value: MapEvent$): boolean;
export function MapEvent$ValueChanged$local(value: MapEvent$): boolean;

export class Cleared extends _.CustomType {
  /** @deprecated */
  constructor(local: boolean);
  /** @deprecated */
  local: boolean;
}
export function MapEvent$Cleared(local: boolean): MapEvent$;
export function MapEvent$isCleared(value: any): value is MapEvent$;
export function MapEvent$Cleared$0(value: MapEvent$): boolean;
export function MapEvent$Cleared$local(value: MapEvent$): boolean;

export type MapEvent$ = ValueChanged | Cleared;

export class UnexpectedAck extends _.CustomType {
  /** @deprecated */
  constructor(operation: MapOperation$, detail: string);
  /** @deprecated */
  operation: MapOperation$;
  /** @deprecated */
  detail: string;
}
export function KernelError$UnexpectedAck(
  operation: MapOperation$,
  detail: string,
): KernelError$;
export function KernelError$isUnexpectedAck(value: any): value is KernelError$;
export function KernelError$UnexpectedAck$0(value: KernelError$): MapOperation$;
export function KernelError$UnexpectedAck$operation(value: KernelError$): MapOperation$;
export function KernelError$UnexpectedAck$1(
  value: KernelError$,
): string;
export function KernelError$UnexpectedAck$detail(value: KernelError$): string;

export type KernelError$ = UnexpectedAck;

export function new$(): MapState$;

export function from_sequenced(entries: _.List<[string, $json.Json$]>): MapState$;

export function sequenced_entries(state: MapState$): _.List<
  [string, $json.Json$]
>;

export function get(state: MapState$, key: string): _.Result<
  $json.Json$,
  undefined
>;

export function has(state: MapState$, key: string): boolean;

export function entries(state: MapState$): _.List<[string, $json.Json$]>;

export function size(state: MapState$): number;

export function keys(state: MapState$): _.List<string>;

export function set(state: MapState$, key: string, value: $json.Json$): [
  MapState$,
  _.List<MapEvent$>,
  MapOperation$
];

export function delete$(state: MapState$, key: string): [
  MapState$,
  _.List<MapEvent$>,
  MapOperation$
];

export function clear(state: MapState$): [
  MapState$,
  _.List<MapEvent$>,
  MapOperation$
];

export function apply_remote(state: MapState$, operation: MapOperation$): [
  MapState$,
  _.List<MapEvent$>
];

export function ack_local(state: MapState$, operation: MapOperation$): _.Result<
  MapState$,
  KernelError$
>;
