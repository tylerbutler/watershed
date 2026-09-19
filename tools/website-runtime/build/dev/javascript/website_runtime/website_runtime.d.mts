import type * as $dict from "../gleam_stdlib/gleam/dict.d.mts";
import type * as $watershed from "../watershed/watershed.d.mts";
import type * as $sluice_js from "../watershed/watershed/sluice_js.d.mts";
import type * as _ from "./gleam.d.mts";

export type Root$ = any;

declare class Client extends _.CustomType {
  /** @deprecated */
  constructor(document: $watershed.Document$<Root$>);
  /** @deprecated */
  document: $watershed.Document$<Root$>;
}

export type Client$ = Client;

declare class Runtime extends _.CustomType {
  /** @deprecated */
  constructor(sluice: $sluice_js.Sluice$, clients: $dict.Dict$<string, Client$>);
  /** @deprecated */
  sluice: $sluice_js.Sluice$;
  /** @deprecated */
  clients: $dict.Dict$<string, Client$>;
}

export type Runtime$ = Runtime;

export type Delivery = $sluice_js.Delivery$;

export function start(
  tenant: string,
  document: string,
  client_ids: _.List<string>
): _.Result<Runtime$, string>;

export function client(runtime: Runtime$, id: string): _.Result<Client$, string>;

export function settle(runtime: Runtime$): undefined;

export function peek(runtime: Runtime$): _.Result<
  $sluice_js.Delivery$,
  undefined
>;

export function step(runtime: Runtime$): _.Result<
  $sluice_js.Delivery$,
  undefined
>;

export function pending(runtime: Runtime$): boolean;

export function sequence_number(runtime: Runtime$): number;

export function pause(runtime: Runtime$, id: string): _.Result<
  undefined,
  string
>;

export function resume(runtime: Runtime$, id: string): _.Result<
  undefined,
  string
>;

export function document(client: Client$): $watershed.Document$<Root$>;
