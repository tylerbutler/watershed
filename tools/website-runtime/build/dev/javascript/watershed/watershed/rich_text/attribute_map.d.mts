import type * as _ from "../../gleam.d.mts";
import type * as $json_ot from "../../watershed/json_ot.d.mts";

declare class Attributes extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<[string, $json_ot.JsonValue$]>);
  /** @deprecated */
  0: _.List<[string, $json_ot.JsonValue$]>;
}

export type Attributes$ = Attributes;

export function empty(): Attributes$;

export function from_list(entries: _.List<[string, $json_ot.JsonValue$]>): Attributes$;

export function to_list(attributes: Attributes$): _.List<
  [string, $json_ot.JsonValue$]
>;

export function is_empty(attributes: Attributes$): boolean;

export function get(attributes: Attributes$, key: string): _.Result<
  $json_ot.JsonValue$,
  undefined
>;

export function without_nulls(attributes: Attributes$): Attributes$;

export function compose(a: Attributes$, b: Attributes$, keep_null: boolean): Attributes$;

export function invert(patch: Attributes$, base: Attributes$): Attributes$;

export function transform(
  base: Attributes$,
  other: Attributes$,
  priority: boolean
): Attributes$;
