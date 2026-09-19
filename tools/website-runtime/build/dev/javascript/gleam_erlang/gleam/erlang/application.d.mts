import type * as _ from "../../gleam.d.mts";
import type * as $node from "../../gleam/erlang/node.d.mts";

export class Normal extends _.CustomType {}
export function StartType$Normal(): StartType$;
export function StartType$isNormal(value: any): value is StartType$;

export class Takeover extends _.CustomType {
  /** @deprecated */
  constructor(previous: $node.Node$);
  /** @deprecated */
  previous: $node.Node$;
}
export function StartType$Takeover(previous: $node.Node$): StartType$;
export function StartType$isTakeover(value: any): value is StartType$;
export function StartType$Takeover$0(value: StartType$): $node.Node$;
export function StartType$Takeover$previous(value: StartType$): $node.Node$;

export class Failover extends _.CustomType {
  /** @deprecated */
  constructor(previous: $node.Node$);
  /** @deprecated */
  previous: $node.Node$;
}
export function StartType$Failover(previous: $node.Node$): StartType$;
export function StartType$isFailover(value: any): value is StartType$;
export function StartType$Failover$0(value: StartType$): $node.Node$;
export function StartType$Failover$previous(value: StartType$): $node.Node$;

export type StartType$ = Normal | Takeover | Failover;

export function priv_directory(name: string): _.Result<string, undefined>;
