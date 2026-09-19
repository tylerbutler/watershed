import type * as $order from "../../gleam_stdlib/gleam/order.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $json_ot from "../watershed/json_ot.d.mts";

declare class Decimal extends _.CustomType {
  /** @deprecated */
  constructor(negative: boolean, digits: string, point: number);
  /** @deprecated */
  negative: boolean;
  /** @deprecated */
  digits: string;
  /** @deprecated */
  point: number;
}

declare class Zero extends _.CustomType {}

type Decimal$ = Decimal | Zero;

export function compare(left: string, right: string): $order.Order$;

export function to_string(value: $json_ot.JsonValue$): string;

export function sorted(items: _.List<$json_ot.JsonValue$>): _.List<
  $json_ot.JsonValue$
>;
