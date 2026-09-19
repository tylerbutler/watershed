import type * as _ from "../../gleam.d.mts";
import type * as $atom from "../../gleam/erlang/atom.d.mts";

export type Node$ = any;

export class FailedToConnect extends _.CustomType {}
export function ConnectError$FailedToConnect(): ConnectError$;
export function ConnectError$isFailedToConnect(
  value: any,
): value is ConnectError$;

export class LocalNodeIsNotAlive extends _.CustomType {}
export function ConnectError$LocalNodeIsNotAlive(): ConnectError$;
export function ConnectError$isLocalNodeIsNotAlive(
  value: any,
): value is ConnectError$;

export type ConnectError$ = FailedToConnect | LocalNodeIsNotAlive;

export function self(): Node$;

export function visible(): _.List<Node$>;

export function connect(node: $atom.Atom$): _.Result<Node$, ConnectError$>;

export function name(node: Node$): $atom.Atom$;
