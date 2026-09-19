import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class OutboundOperation extends _.CustomType {
  /** @deprecated */
  constructor(
    client_sequence_number: number,
    reference_sequence_number: number,
    operation_type: string,
    contents: $json.Json$,
    metadata: $option.Option$<$json.Json$>
  );
  /** @deprecated */
  client_sequence_number: number;
  /** @deprecated */
  reference_sequence_number: number;
  /** @deprecated */
  operation_type: string;
  /** @deprecated */
  contents: $json.Json$;
  /** @deprecated */
  metadata: $option.Option$<$json.Json$>;
}
export function OutboundOperation$OutboundOperation(
  client_sequence_number: number,
  reference_sequence_number: number,
  operation_type: string,
  contents: $json.Json$,
  metadata: $option.Option$<$json.Json$>,
): OutboundOperation$;
export function OutboundOperation$isOutboundOperation(
  value: any,
): value is OutboundOperation$;
export function OutboundOperation$OutboundOperation$0(value: OutboundOperation$): number;
export function OutboundOperation$OutboundOperation$client_sequence_number(
  value: OutboundOperation$,
): number;
export function OutboundOperation$OutboundOperation$1(value: OutboundOperation$): number;
export function OutboundOperation$OutboundOperation$reference_sequence_number(
  value: OutboundOperation$,
): number;
export function OutboundOperation$OutboundOperation$2(value: OutboundOperation$): string;
export function OutboundOperation$OutboundOperation$operation_type(
  value: OutboundOperation$,
): string;
export function OutboundOperation$OutboundOperation$3(value: OutboundOperation$): $json.Json$;
export function OutboundOperation$OutboundOperation$contents(
  value: OutboundOperation$,
): $json.Json$;
export function OutboundOperation$OutboundOperation$4(value: OutboundOperation$): $option.Option$<
  $json.Json$
>;
export function OutboundOperation$OutboundOperation$metadata(value: OutboundOperation$): $option.Option$<
  $json.Json$
>;

export type OutboundOperation$ = OutboundOperation;

declare class ComparableNull extends _.CustomType {}

declare class ComparableBool extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: boolean);
  /** @deprecated */
  0: boolean;
}

declare class ComparableString extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}

declare class ComparableNumber extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}

declare class ComparableInteger extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}

declare class ComparableArray extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<ComparableJson$>);
  /** @deprecated */
  0: _.List<ComparableJson$>;
}

declare class ComparableObject extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<[string, ComparableJson$]>);
  /** @deprecated */
  0: _.List<[string, ComparableJson$]>;
}

type ComparableJson$ = ComparableNull | ComparableBool | ComparableString | ComparableNumber | ComparableInteger | ComparableArray | ComparableObject;

export const channel_type_map: string;

export const channel_type_counter: string;

export const channel_type_pn_counter: string;

export const channel_type_g_counter: string;

export const channel_type_lww_register: string;

export const channel_type_lww_map: string;

export const channel_type_mv_register: string;

export const channel_type_or_map: string;

export const channel_type_or_set: string;

export const channel_type_g_set: string;

export const channel_type_two_p_set: string;

export const channel_type_register_collection: string;

export const channel_type_claims: string;

export const channel_type_task_manager: string;

export const channel_type_pact_map: string;

export const channel_type_ordered_collection: string;

export const channel_type_json_ot: string;

export const channel_type_directory: string;

export const channel_type_sequence: string;

export const channel_type_rich_text: string;

export const channel_type_text: string;

export function encode_entries(entries: _.List<[string, $json.Json$]>): $json.Json$;

export function json_value_decoder(): $decode.Decoder$<$json.Json$>;

export function entry_decoder(): $decode.Decoder$<[string, $json.Json$]>;

export function dynamic_to_json(value: $dynamic.Dynamic$): $json.Json$;

export function json_semantically_equal(ours: $json.Json$, echoed: $json.Json$): boolean;
