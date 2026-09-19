import type * as $charlist from "../../gleam_erlang/gleam/erlang/charlist.d.mts";
import type * as $http from "../../gleam_http/gleam/http.d.mts";
import type * as $request from "../../gleam_http/gleam/http/request.d.mts";
import type * as $response from "../../gleam_http/gleam/http/response.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "../gleam.d.mts";

export class InvalidUtf8Response extends _.CustomType {}
export function HttpError$InvalidUtf8Response(): HttpError$;
export function HttpError$isInvalidUtf8Response(
  value: any,
): value is HttpError$;

export class FailedToConnect extends _.CustomType {
  /** @deprecated */
  constructor(ip4: ConnectError$, ip6: ConnectError$);
  /** @deprecated */
  ip4: ConnectError$;
  /** @deprecated */
  ip6: ConnectError$;
}
export function HttpError$FailedToConnect(
  ip4: ConnectError$,
  ip6: ConnectError$,
): HttpError$;
export function HttpError$isFailedToConnect(value: any): value is HttpError$;
export function HttpError$FailedToConnect$0(value: HttpError$): ConnectError$;
export function HttpError$FailedToConnect$ip4(value: HttpError$): ConnectError$;
export function HttpError$FailedToConnect$1(value: HttpError$): ConnectError$;
export function HttpError$FailedToConnect$ip6(value: HttpError$): ConnectError$;

export class ResponseTimeout extends _.CustomType {}
export function HttpError$ResponseTimeout(): HttpError$;
export function HttpError$isResponseTimeout(value: any): value is HttpError$;

export type HttpError$ = InvalidUtf8Response | FailedToConnect | ResponseTimeout;

export class Posix extends _.CustomType {
  /** @deprecated */
  constructor(code: string);
  /** @deprecated */
  code: string;
}
export function ConnectError$Posix(code: string): ConnectError$;
export function ConnectError$isPosix(value: any): value is ConnectError$;
export function ConnectError$Posix$0(value: ConnectError$): string;
export function ConnectError$Posix$code(value: ConnectError$): string;

export class TlsAlert extends _.CustomType {
  /** @deprecated */
  constructor(code: string, detail: string);
  /** @deprecated */
  code: string;
  /** @deprecated */
  detail: string;
}
export function ConnectError$TlsAlert(
  code: string,
  detail: string,
): ConnectError$;
export function ConnectError$isTlsAlert(value: any): value is ConnectError$;
export function ConnectError$TlsAlert$0(value: ConnectError$): string;
export function ConnectError$TlsAlert$code(value: ConnectError$): string;
export function ConnectError$TlsAlert$1(value: ConnectError$): string;
export function ConnectError$TlsAlert$detail(value: ConnectError$): string;

export type ConnectError$ = Posix | TlsAlert;

export function ConnectError$code(value: ConnectError$): string;

declare class Ssl extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<ErlSslOption$>);
  /** @deprecated */
  0: _.List<ErlSslOption$>;
}

declare class Autoredirect extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: boolean);
  /** @deprecated */
  0: boolean;
}

declare class Timeout extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}

type ErlHttpOption$ = Ssl | Autoredirect | Timeout;

declare class Binary extends _.CustomType {}

type BodyFormat$ = Binary;

declare class BodyFormat extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: BodyFormat$);
  /** @deprecated */
  0: BodyFormat$;
}

declare class SocketOpts extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.List<SocketOpt$>);
  /** @deprecated */
  0: _.List<SocketOpt$>;
}

type ErlOption$ = BodyFormat | SocketOpts;

declare class Ipfamily extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: Inet6fb4$);
  /** @deprecated */
  0: Inet6fb4$;
}

type SocketOpt$ = Ipfamily;

declare class Inet6fb4 extends _.CustomType {}

type Inet6fb4$ = Inet6fb4;

declare class Verify extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: ErlVerifyOption$);
  /** @deprecated */
  0: ErlVerifyOption$;
}

type ErlSslOption$ = Verify;

declare class VerifyNone extends _.CustomType {}

type ErlVerifyOption$ = VerifyNone;

declare class Builder extends _.CustomType {
  /** @deprecated */
  constructor(verify_tls: boolean, follow_redirects: boolean, timeout: number);
  /** @deprecated */
  verify_tls: boolean;
  /** @deprecated */
  follow_redirects: boolean;
  /** @deprecated */
  timeout: number;
}

export type Configuration$ = Builder;

export function dispatch_bits(
  config: Configuration$,
  req: $request.Request$<_.BitArray>
): _.Result<$response.Response$<_.BitArray>, HttpError$>;

export function configure(): Configuration$;

export function send_bits(req: $request.Request$<_.BitArray>): _.Result<
  $response.Response$<_.BitArray>,
  HttpError$
>;

export function verify_tls(config: Configuration$, which: boolean): Configuration$;

export function follow_redirects(config: Configuration$, which: boolean): Configuration$;

export function timeout(config: Configuration$, timeout: number): Configuration$;

export function dispatch(
  config: Configuration$,
  request: $request.Request$<string>
): _.Result<$response.Response$<string>, HttpError$>;

export function send(req: $request.Request$<string>): _.Result<
  $response.Response$<string>,
  HttpError$
>;
