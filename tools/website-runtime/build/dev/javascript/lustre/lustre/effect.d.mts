import type * as $process from "../../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";

declare class Effect<UDK> extends _.CustomType {
  /** @deprecated */
  constructor(
    synchronous: _.List<(x0: Actions$<UDK>) => undefined>,
    before_paint: _.List<(x0: Actions$<UDK>) => undefined>,
    after_paint: _.List<(x0: Actions$<UDK>) => undefined>
  );
  /** @deprecated */
  synchronous: _.List<(x0: Actions$<UDK>) => undefined>;
  /** @deprecated */
  before_paint: _.List<(x0: Actions$<UDK>) => undefined>;
  /** @deprecated */
  after_paint: _.List<(x0: Actions$<UDK>) => undefined>;
}

export type Effect$<UDK> = Effect<UDK>;

declare class Actions<UDL> extends _.CustomType {
  /** @deprecated */
  constructor(
    dispatch: (x0: UDL) => undefined,
    emit: (x0: string, x1: $json.Json$) => undefined,
    select: (x0: $process.Selector$<UDL>) => undefined,
    root: () => $dynamic.Dynamic$,
    provide: (x0: string, x1: $json.Json$) => undefined,
    subscribe: (x0: string, x1: $decode.Decoder$<UDL>) => undefined,
    unsubscribe: (x0: string) => undefined
  );
  /** @deprecated */
  dispatch: (x0: UDL) => undefined;
  /** @deprecated */
  emit: (x0: string, x1: $json.Json$) => undefined;
  /** @deprecated */
  select: (x0: $process.Selector$<UDL>) => undefined;
  /** @deprecated */
  root: () => $dynamic.Dynamic$;
  /** @deprecated */
  provide: (x0: string, x1: $json.Json$) => undefined;
  /** @deprecated */
  subscribe: (x0: string, x1: $decode.Decoder$<UDL>) => undefined;
  /** @deprecated */
  unsubscribe: (x0: string) => undefined;
}

type Actions$<UDL> = Actions<UDL>;

export function none(): Effect$<any>;

export function from<UDO>(effect: (x0: (x0: UDO) => undefined) => undefined): Effect$<
  UDO
>;

export function before_paint<UDQ>(
  effect: (x0: (x0: UDQ) => undefined, x1: $dynamic.Dynamic$) => undefined
): Effect$<UDQ>;

export function after_paint<UDS>(
  effect: (x0: (x0: UDS) => undefined, x1: $dynamic.Dynamic$) => undefined
): Effect$<UDS>;

export function event(name: string, data: $json.Json$): Effect$<any>;

export function select(x0: any): Effect$<any>;

export function provide(key: string, value: $json.Json$): Effect$<any>;

export function subscribe<UEA>(key: string, decoder: $decode.Decoder$<UEA>): Effect$<
  UEA
>;

export function unsubscribe(key: string): Effect$<any>;

export function batch<UEF>(effects: _.List<Effect$<UEF>>): Effect$<UEF>;

export function map<UEJ, UEL>(effect: Effect$<UEJ>, f: (x0: UEJ) => UEL): Effect$<
  UEL
>;

export function perform<UFA>(
  effect: Effect$<UFA>,
  dispatch: (x0: UFA) => undefined,
  emit: (x0: string, x1: $json.Json$) => undefined,
  select: (x0: $process.Selector$<UFA>) => undefined,
  root: () => $dynamic.Dynamic$,
  provide: (x0: string, x1: $json.Json$) => undefined,
  subscribe: (x0: string, x1: $decode.Decoder$<UFA>) => undefined,
  unsubscribe: (x0: string) => undefined
): undefined;
