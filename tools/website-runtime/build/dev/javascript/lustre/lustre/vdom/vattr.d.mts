import type * as $json from "../../../gleam_json/gleam/json.d.mts";
import type * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $order from "../../../gleam_stdlib/gleam/order.d.mts";
import type * as $string_tree from "../../../gleam_stdlib/gleam/string_tree.d.mts";
import type * as _ from "../../gleam.d.mts";

export class Attribute extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, name: string, value: string);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  name: string;
  /** @deprecated */
  value: string;
}
export function Attribute$Attribute<TDZ>(
  kind: number,
  name: string,
  value: string,
): Attribute$<TDZ>;
export function Attribute$isAttribute<TDZ>(
  value: any,
): value is Attribute$<unknown>;
export function Attribute$Attribute$0<TDZ>(value: Attribute$<TDZ>): number;
export function Attribute$Attribute$kind<TDZ>(value: Attribute$<TDZ>): number;
export function Attribute$Attribute$1<TDZ>(value: Attribute$<TDZ>): string;
export function Attribute$Attribute$name<TDZ>(value: Attribute$<TDZ>): string;
export function Attribute$Attribute$2<TDZ>(value: Attribute$<TDZ>): string;
export function Attribute$Attribute$value<TDZ>(value: Attribute$<TDZ>): string;

export class Property extends _.CustomType {
  /** @deprecated */
  constructor(kind: number, name: string, value: $json.Json$);
  /** @deprecated */
  kind: number;
  /** @deprecated */
  name: string;
  /** @deprecated */
  value: $json.Json$;
}
export function Attribute$Property<TDZ>(
  kind: number,
  name: string,
  value: $json.Json$,
): Attribute$<TDZ>;
export function Attribute$isProperty<TDZ>(
  value: any,
): value is Attribute$<unknown>;
export function Attribute$Property$0<TDZ>(value: Attribute$<TDZ>): number;
export function Attribute$Property$kind<TDZ>(value: Attribute$<TDZ>): number;
export function Attribute$Property$1<TDZ>(value: Attribute$<TDZ>): string;
export function Attribute$Property$name<TDZ>(value: Attribute$<TDZ>): string;
export function Attribute$Property$2<TDZ>(value: Attribute$<TDZ>): $json.Json$;
export function Attribute$Property$value<TDZ>(value: Attribute$<TDZ>): $json.Json$;

export class Event<TDZ> extends _.CustomType {
  /** @deprecated */
  constructor(
    kind: number,
    name: string,
    handler: $decode.Decoder$<Handler$<TDZ>>,
    include: _.List<string>,
    prevent_default: EventBehaviour$,
    stop_propagation: EventBehaviour$,
    debounce: number,
    throttle: number
  );
  /** @deprecated */
  kind: number;
  /** @deprecated */
  name: string;
  /** @deprecated */
  handler: $decode.Decoder$<Handler$<TDZ>>;
  /** @deprecated */
  include: _.List<string>;
  /** @deprecated */
  prevent_default: EventBehaviour$;
  /** @deprecated */
  stop_propagation: EventBehaviour$;
  /** @deprecated */
  debounce: number;
  /** @deprecated */
  throttle: number;
}
export function Attribute$Event<TDZ>(
  kind: number,
  name: string,
  handler: $decode.Decoder$<Handler$<TDZ>>,
  include: _.List<string>,
  prevent_default: EventBehaviour$,
  stop_propagation: EventBehaviour$,
  debounce: number,
  throttle: number,
): Attribute$<TDZ>;
export function Attribute$isEvent<TDZ>(
  value: any,
): value is Attribute$<unknown>;
export function Attribute$Event$0<TDZ>(value: Attribute$<TDZ>): number;
export function Attribute$Event$kind<TDZ>(value: Attribute$<TDZ>): number;
export function Attribute$Event$1<TDZ>(value: Attribute$<TDZ>): string;
export function Attribute$Event$name<TDZ>(value: Attribute$<TDZ>): string;
export function Attribute$Event$2<TDZ>(value: Attribute$<TDZ>): $decode.Decoder$<
  Handler$<TDZ>
>;
export function Attribute$Event$handler<TDZ>(value: Attribute$<TDZ>): $decode.Decoder$<
  Handler$<TDZ>
>;
export function Attribute$Event$3<TDZ>(value: Attribute$<TDZ>): _.List<string>;
export function Attribute$Event$include<TDZ>(value: Attribute$<TDZ>): _.List<
  string
>;
export function Attribute$Event$4<TDZ>(value: Attribute$<TDZ>): EventBehaviour$;
export function Attribute$Event$prevent_default<TDZ>(value: Attribute$<TDZ>): EventBehaviour$;
export function Attribute$Event$5<TDZ>(
  value: Attribute$<TDZ>,
): EventBehaviour$;
export function Attribute$Event$stop_propagation<TDZ>(value: Attribute$<TDZ>): EventBehaviour$;
export function Attribute$Event$6<TDZ>(
  value: Attribute$<TDZ>,
): number;
export function Attribute$Event$debounce<TDZ>(value: Attribute$<TDZ>): number;
export function Attribute$Event$7<TDZ>(value: Attribute$<TDZ>): number;
export function Attribute$Event$throttle<TDZ>(value: Attribute$<TDZ>): number;

export type Attribute$<TDZ> = Attribute | Property | Event<TDZ>;

export function Attribute$kind<TDZ>(value: Attribute$<TDZ>): number;
export function Attribute$name<TDZ>(value: Attribute$<TDZ>): string;

export class Handler<TEA> extends _.CustomType {
  /** @deprecated */
  constructor(prevent_default: boolean, stop_propagation: boolean, message: TEA);
  /** @deprecated */
  prevent_default: boolean;
  /** @deprecated */
  stop_propagation: boolean;
  /** @deprecated */
  message: TEA;
}
export function Handler$Handler<TEA>(
  prevent_default: boolean,
  stop_propagation: boolean,
  message: TEA,
): Handler$<TEA>;
export function Handler$isHandler<TEA>(value: any): value is Handler$<unknown>;
export function Handler$Handler$0<TEA>(value: Handler$<TEA>): boolean;
export function Handler$Handler$prevent_default<TEA>(value: Handler$<TEA>): boolean;
export function Handler$Handler$1<TEA>(
  value: Handler$<TEA>,
): boolean;
export function Handler$Handler$stop_propagation<TEA>(value: Handler$<TEA>): boolean;
export function Handler$Handler$2<TEA>(
  value: Handler$<TEA>,
): TEA;
export function Handler$Handler$message<TEA>(value: Handler$<TEA>): TEA;

export type Handler$<TEA> = Handler<TEA>;

export class Never extends _.CustomType {
  /** @deprecated */
  constructor(kind: number);
  /** @deprecated */
  kind: number;
}
export function EventBehaviour$Never(kind: number): EventBehaviour$;
export function EventBehaviour$isNever(value: any): value is EventBehaviour$;
export function EventBehaviour$Never$0(value: EventBehaviour$): number;
export function EventBehaviour$Never$kind(value: EventBehaviour$): number;

export class Possible extends _.CustomType {
  /** @deprecated */
  constructor(kind: number);
  /** @deprecated */
  kind: number;
}
export function EventBehaviour$Possible(kind: number): EventBehaviour$;
export function EventBehaviour$isPossible(value: any): value is EventBehaviour$;
export function EventBehaviour$Possible$0(value: EventBehaviour$): number;
export function EventBehaviour$Possible$kind(value: EventBehaviour$): number;

export class Always extends _.CustomType {
  /** @deprecated */
  constructor(kind: number);
  /** @deprecated */
  kind: number;
}
export function EventBehaviour$Always(kind: number): EventBehaviour$;
export function EventBehaviour$isAlways(value: any): value is EventBehaviour$;
export function EventBehaviour$Always$0(value: EventBehaviour$): number;
export function EventBehaviour$Always$kind(value: EventBehaviour$): number;

export type EventBehaviour$ = Never | Possible | Always;

export function EventBehaviour$kind(value: EventBehaviour$): number;

export const attribute_kind: number;

export const property_kind: number;

export const event_kind: number;

export const never_kind: number;

export const never: EventBehaviour$;

export const possible_kind: number;

export const possible: EventBehaviour$;

export const always_kind: number;

export const always: EventBehaviour$;

export function attribute(name: string, value: string): Attribute$<any>;

export function property(name: string, value: $json.Json$): Attribute$<any>;

export function event<TEF>(
  name: string,
  handler: $decode.Decoder$<Handler$<TEF>>,
  include: _.List<string>,
  prevent_default: EventBehaviour$,
  stop_propagation: EventBehaviour$,
  debounce: number,
  throttle: number
): Attribute$<TEF>;

export function merge<TEP>(
  attributes: _.List<Attribute$<TEP>>,
  merged: _.List<Attribute$<TEP>>
): _.List<Attribute$<TEP>>;

export function compare<TEW>(a: Attribute$<TEW>, b: Attribute$<TEW>): $order.Order$;

export function prepare<TEK>(attributes: _.List<Attribute$<TEK>>): _.List<
  Attribute$<TEK>
>;

export function to_json(attribute: Attribute$<any>): $json.Json$;

export function to_string_tree(
  key: string,
  namespace: string,
  parent_namespace: string,
  attributes: _.List<Attribute$<any>>
): $string_tree.StringTree$;
