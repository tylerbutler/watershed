import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $set from "../../gleam_stdlib/gleam/set.d.mts";
import type * as _ from "../gleam.d.mts";

declare class TwoPSet<OJG> extends _.CustomType {
  /** @deprecated */
  constructor(added: $set.Set$<OJG>, removed: $set.Set$<OJG>);
  /** @deprecated */
  added: $set.Set$<OJG>;
  /** @deprecated */
  removed: $set.Set$<OJG>;
}

export type TwoPSet$<OJG> = TwoPSet<OJG>;

export function new$(): TwoPSet$<any>;

export function add_with_delta<OJM>(two_p_set: TwoPSet$<OJM>, element: OJM): [
  TwoPSet$<OJM>,
  TwoPSet$<OJM>
];

export function add<OJJ>(two_p_set: TwoPSet$<OJJ>, element: OJJ): TwoPSet$<OJJ>;

export function remove_with_delta<OJT>(two_p_set: TwoPSet$<OJT>, element: OJT): [
  TwoPSet$<OJT>,
  TwoPSet$<OJT>
];

export function remove<OJQ>(two_p_set: TwoPSet$<OJQ>, element: OJQ): TwoPSet$<
  OJQ
>;

export function contains<OJX>(two_p_set: TwoPSet$<OJX>, element: OJX): boolean;

export function value<OJZ>(two_p_set: TwoPSet$<OJZ>): $set.Set$<OJZ>;

export function merge<OKC>(a: TwoPSet$<OKC>, b: TwoPSet$<OKC>): TwoPSet$<OKC>;

export function to_json_with<OKH>(
  two_p_set: TwoPSet$<OKH>,
  encode: (x0: OKH) => $json.Json$
): $json.Json$;

export function to_json(two_p_set: TwoPSet$<string>): $json.Json$;

export function from_json_with<OKM>(
  json_string: string,
  decoder: $decode.Decoder$<OKM>
): _.Result<TwoPSet$<OKM>, $json.DecodeError$>;

export function from_json(json_string: string): _.Result<
  TwoPSet$<string>,
  $json.DecodeError$
>;
