import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $error from "../gluegun/error.d.mts";
import type * as $fin from "../gluegun/fin.d.mts";
import type * as $internal from "../gluegun/internal.d.mts";

export class Get extends _.CustomType {}
export function Method$Get(): Method$;
export function Method$isGet(value: any): value is Method$;

export class Head extends _.CustomType {}
export function Method$Head(): Method$;
export function Method$isHead(value: any): value is Method$;

export class Post extends _.CustomType {}
export function Method$Post(): Method$;
export function Method$isPost(value: any): value is Method$;

export class Put extends _.CustomType {}
export function Method$Put(): Method$;
export function Method$isPut(value: any): value is Method$;

export class Patch extends _.CustomType {}
export function Method$Patch(): Method$;
export function Method$isPatch(value: any): value is Method$;

export class Delete extends _.CustomType {}
export function Method$Delete(): Method$;
export function Method$isDelete(value: any): value is Method$;

export class Options extends _.CustomType {}
export function Method$Options(): Method$;
export function Method$isOptions(value: any): value is Method$;

export class Trace extends _.CustomType {}
export function Method$Trace(): Method$;
export function Method$isTrace(value: any): value is Method$;

export class Connect extends _.CustomType {}
export function Method$Connect(): Method$;
export function Method$isConnect(value: any): value is Method$;

export class Custom extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function Method$Custom($0: string): Method$;
export function Method$isCustom(value: any): value is Method$;
export function Method$Custom$0(value: Method$): string;

export type Method$ = Get | Head | Post | Put | Patch | Delete | Options | Trace | Connect | Custom;

declare class RequestOptions extends _.CustomType {
  /** @deprecated */
  constructor(headers: _.List<[string, string]>, reserved: undefined);
  /** @deprecated */
  headers: _.List<[string, string]>;
  /** @deprecated */
  reserved: undefined;
}

export type RequestOptions$ = RequestOptions;

export type Header = [string, string];

export function options(): RequestOptions$;

export function with_headers(
  options: RequestOptions$,
  headers: _.List<[string, string]>
): RequestOptions$;

export function set_headers(
  options: RequestOptions$,
  headers: _.List<[string, string]>
): RequestOptions$;

export function headers_option(options: RequestOptions$): _.List<
  [string, string]
>;

export function method_to_string(method: Method$): string;

export function normalize_headers(headers: _.List<[string, string]>): _.List<
  [string, string]
>;

export function request(
  connection: $internal.Connection$,
  method: Method$,
  path: string,
  headers: _.List<[string, string]>,
  body: _.BitArray,
  options: RequestOptions$
): _.Result<$internal.Stream$, $error.GluegunError$>;

export function headers_args_to_ffi(
  method: Method$,
  path: string,
  headers: _.List<[string, string]>,
  options: RequestOptions$
): [string, string, _.List<[string, string]>, $dynamic.Dynamic$];

export function headers(
  connection: $internal.Connection$,
  method: Method$,
  path: string,
  headers: _.List<[string, string]>,
  options: RequestOptions$
): _.Result<$internal.Stream$, $error.GluegunError$>;

export function data(
  connection: $internal.Connection$,
  stream: $internal.Stream$,
  fin: $fin.Fin$,
  data: _.BitArray
): _.Result<undefined, $error.GluegunError$>;

export function cancel(
  connection: $internal.Connection$,
  stream: $internal.Stream$
): _.Result<undefined, $error.GluegunError$>;

export function update_flow_args_to_ffi(
  connection: $internal.Connection$,
  stream: $internal.Stream$,
  increment: number
): [$dynamic.Dynamic$, $dynamic.Dynamic$, number];

export function update_flow(
  connection: $internal.Connection$,
  stream: $internal.Stream$,
  increment: number
): _.Result<undefined, $error.GluegunError$>;

export function flush(connection: $internal.Connection$): _.Result<
  undefined,
  $error.GluegunError$
>;

export function fin_to_ffi(fin: $fin.Fin$): $dynamic.Dynamic$;
