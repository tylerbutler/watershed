import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $watershed from "../watershed.d.mts";
import type * as $runtime from "../watershed/runtime.d.mts";
import type * as $core from "../watershed/sluice/core.d.mts";
import type * as $transport_js from "../watershed/transport_js.d.mts";

declare class Sluice extends _.CustomType {
  /** @deprecated */
  constructor(
    cell: $transport_js.Cell$<State$>,
    tenant: string,
    document: string
  );
  /** @deprecated */
  cell: $transport_js.Cell$<State$>;
  /** @deprecated */
  tenant: string;
  /** @deprecated */
  document: string;
}

export type Sluice$ = Sluice;

export class Delivery extends _.CustomType {
  /** @deprecated */
  constructor(
    to: string,
    event: string,
    sequence_number: number,
    author: string
  );
  /** @deprecated */
  to: string;
  /** @deprecated */
  event: string;
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  author: string;
}
export function Delivery$Delivery(
  to: string,
  event: string,
  sequence_number: number,
  author: string,
): Delivery$;
export function Delivery$isDelivery(value: any): value is Delivery$;
export function Delivery$Delivery$0(value: Delivery$): string;
export function Delivery$Delivery$to(value: Delivery$): string;
export function Delivery$Delivery$1(value: Delivery$): string;
export function Delivery$Delivery$event(value: Delivery$): string;
export function Delivery$Delivery$2(value: Delivery$): number;
export function Delivery$Delivery$sequence_number(value: Delivery$): number;
export function Delivery$Delivery$3(value: Delivery$): string;
export function Delivery$Delivery$author(value: Delivery$): string;

export type Delivery$ = Delivery;

declare class Conn extends _.CustomType {
  /** @deprecated */
  constructor(
    on_event: (x0: string, x1: string) => undefined,
    on_join: () => undefined,
    on_close: () => undefined,
    current: string,
    dropped: boolean
  );
  /** @deprecated */
  on_event: (x0: string, x1: string) => undefined;
  /** @deprecated */
  on_join: () => undefined;
  /** @deprecated */
  on_close: () => undefined;
  /** @deprecated */
  current: string;
  /** @deprecated */
  dropped: boolean;
}

type Conn$ = Conn;

declare class State extends _.CustomType {
  /** @deprecated */
  constructor(
    core: $core.Sluice$,
    conns: _.List<[string, Conn$]>,
    bindings: _.List<[$runtime.Runtime$, string]>,
    last_registered: $option.Option$<string>,
    timers: _.List<[number, number, () => undefined]>,
    next_timer_id: number
  );
  /** @deprecated */
  core: $core.Sluice$;
  /** @deprecated */
  conns: _.List<[string, Conn$]>;
  /** @deprecated */
  bindings: _.List<[$runtime.Runtime$, string]>;
  /** @deprecated */
  last_registered: $option.Option$<string>;
  /** @deprecated */
  timers: _.List<[number, number, () => undefined]>;
  /** @deprecated */
  next_timer_id: number;
}

type State$ = State;

export function start(tenant: string, document: string): Sluice$;

export function scheduler(sluice: Sluice$): $transport_js.Scheduler$;

export function connect(sluice: Sluice$, user_id: string): $watershed.Document$<
  any
>;

export function pause(sluice: Sluice$, document: $watershed.Document$<any>): undefined;

export function resume(sluice: Sluice$, document: $watershed.Document$<any>): undefined;

export function disconnect(sluice: Sluice$, document: $watershed.Document$<any>): undefined;

export function rejoin(sluice: Sluice$, document: $watershed.Document$<any>): undefined;

export function drop(sluice: Sluice$, document: $watershed.Document$<any>): undefined;

export function reconnect(sluice: Sluice$, document: $watershed.Document$<any>): undefined;

export function settle(sluice: Sluice$): undefined;

export function step(sluice: Sluice$): boolean;

export function step_info(sluice: Sluice$): _.Result<Delivery$, undefined>;

export function peek_info(sluice: Sluice$): _.Result<Delivery$, undefined>;

export function pending(sluice: Sluice$): boolean;

export function client_id(sluice: Sluice$, document: $watershed.Document$<any>): _.Result<
  string,
  undefined
>;

export function sequence_number(sluice: Sluice$): number;

export function advance(sluice: Sluice$, milliseconds: number): undefined;

export function disable_presence(sluice: Sluice$): undefined;
