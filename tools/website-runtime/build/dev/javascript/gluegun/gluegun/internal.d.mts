import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "../gleam.d.mts";

declare class Connection extends _.CustomType {
  /** @deprecated */
  constructor(raw: $dynamic.Dynamic$);
  /** @deprecated */
  raw: $dynamic.Dynamic$;
}

export type Connection$ = Connection;

declare class Stream extends _.CustomType {
  /** @deprecated */
  constructor(raw: $dynamic.Dynamic$);
  /** @deprecated */
  raw: $dynamic.Dynamic$;
}

export type Stream$ = Stream;

export function connection(raw: $dynamic.Dynamic$): Connection$;

export function connection_raw(connection: Connection$): $dynamic.Dynamic$;

export function stream(raw: $dynamic.Dynamic$): Stream$;

export function stream_raw(stream: Stream$): $dynamic.Dynamic$;
