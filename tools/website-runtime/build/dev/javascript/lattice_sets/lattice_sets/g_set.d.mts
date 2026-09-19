import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $set from "../../gleam_stdlib/gleam/set.d.mts";
import type * as _ from "../gleam.d.mts";

declare class GSet<NNO> extends _.CustomType {
  /** @deprecated */
  constructor(elements: $set.Set$<NNO>);
  /** @deprecated */
  elements: $set.Set$<NNO>;
}

export type GSet$<NNO> = GSet<NNO>;

export function new$(): GSet$<any>;

export function add_with_delta<NNU>(g_set: GSet$<NNU>, element: NNU): [
  GSet$<NNU>,
  GSet$<NNU>
];

export function add<NNR>(g_set: GSet$<NNR>, element: NNR): GSet$<NNR>;

export function contains<NNY>(g_set: GSet$<NNY>, element: NNY): boolean;

export function value<NOA>(g_set: GSet$<NOA>): $set.Set$<NOA>;

export function merge<NOD>(a: GSet$<NOD>, b: GSet$<NOD>): GSet$<NOD>;

export function to_json_with<NOI>(
  g_set: GSet$<NOI>,
  encode: (x0: NOI) => $json.Json$
): $json.Json$;

export function to_json(g_set: GSet$<string>): $json.Json$;

export function from_json_with<NON>(
  json_string: string,
  decoder: $decode.Decoder$<NON>
): _.Result<GSet$<NON>, $json.DecodeError$>;

export function from_json(json_string: string): _.Result<
  GSet$<string>,
  $json.DecodeError$
>;
