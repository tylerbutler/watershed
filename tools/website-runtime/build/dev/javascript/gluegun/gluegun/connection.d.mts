import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $error from "../gluegun/error.d.mts";
import type * as $internal from "../gluegun/internal.d.mts";

export class Auto extends _.CustomType {}
export function Transport$Auto(): Transport$;
export function Transport$isAuto(value: any): value is Transport$;

export class Tcp extends _.CustomType {}
export function Transport$Tcp(): Transport$;
export function Transport$isTcp(value: any): value is Transport$;

export class Tls extends _.CustomType {}
export function Transport$Tls(): Transport$;
export function Transport$isTls(value: any): value is Transport$;

export type Transport$ = Auto | Tcp | Tls;

export class Http1 extends _.CustomType {}
export function Protocol$Http1(): Protocol$;
export function Protocol$isHttp1(value: any): value is Protocol$;

export class Http2 extends _.CustomType {}
export function Protocol$Http2(): Protocol$;
export function Protocol$isHttp2(value: any): value is Protocol$;

export type Protocol$ = Http1 | Http2;

export class Milliseconds extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}
export function Timeout$Milliseconds($0: number): Timeout$;
export function Timeout$isMilliseconds(value: any): value is Timeout$;
export function Timeout$Milliseconds$0(value: Timeout$): number;

export class Infinity extends _.CustomType {}
export function Timeout$Infinity(): Timeout$;
export function Timeout$isInfinity(value: any): value is Timeout$;

export type Timeout$ = Milliseconds | Infinity;

declare class ConnectOptions extends _.CustomType {
  /** @deprecated */
  constructor(
    transport: Transport$,
    protocols: $option.Option$<_.List<Protocol$>>,
    retry: Timeout$,
    connect_timeout: Timeout$
  );
  /** @deprecated */
  transport: Transport$;
  /** @deprecated */
  protocols: $option.Option$<_.List<Protocol$>>;
  /** @deprecated */
  retry: Timeout$;
  /** @deprecated */
  connect_timeout: Timeout$;
}

export type ConnectOptions$ = ConnectOptions;

export function options(): ConnectOptions$;

export function with_transport(options: ConnectOptions$, transport: Transport$): ConnectOptions$;

export function with_protocols(
  options: ConnectOptions$,
  protocols: _.List<Protocol$>
): ConnectOptions$;

export function with_retry(options: ConnectOptions$, retry: Timeout$): ConnectOptions$;

export function with_connect_timeout(
  options: ConnectOptions$,
  timeout: Timeout$
): ConnectOptions$;

export function transport(options: ConnectOptions$): Transport$;

export function protocols(options: ConnectOptions$): $option.Option$<
  _.List<Protocol$>
>;

export function retry(options: ConnectOptions$): Timeout$;

export function connect_timeout(options: ConnectOptions$): Timeout$;

export function timeout_to_ffi(timeout: Timeout$): $dynamic.Dynamic$;

export function options_to_ffi(options: ConnectOptions$): $dynamic.Dynamic$;

export function open(options: ConnectOptions$, host: string, port: number): _.Result<
  $internal.Connection$,
  $error.GluegunError$
>;

export function decode_await_up_result(
  await_result: _.Result<$dynamic.Dynamic$, $dynamic.Dynamic$>
): _.Result<Protocol$, $error.GluegunError$>;

export function await_up(connection: $internal.Connection$, timeout: Timeout$): _.Result<
  Protocol$,
  $error.GluegunError$
>;

export function close(connection: $internal.Connection$): _.Result<
  undefined,
  $error.GluegunError$
>;

export function shutdown(connection: $internal.Connection$): _.Result<
  undefined,
  $error.GluegunError$
>;
