import type * as _ from "../gleam.d.mts";
import type * as $connection from "../gluegun/connection.d.mts";
import type * as $error from "../gluegun/error.d.mts";
import type * as $internal from "../gluegun/internal.d.mts";
import type * as $message from "../gluegun/message.d.mts";
import type * as $request from "../gluegun/request.d.mts";
import type * as $response from "../gluegun/response.d.mts";

declare class Request extends _.CustomType {
  /** @deprecated */
  constructor(
    method: $low_request.Method$,
    path: string,
    headers: _.List<[string, string]>,
    body: _.BitArray,
    options: $low_request.RequestOptions$,
    timeout: $connection.Timeout$
  );
  /** @deprecated */
  method: $low_request.Method$;
  /** @deprecated */
  path: string;
  /** @deprecated */
  headers: _.List<[string, string]>;
  /** @deprecated */
  body: _.BitArray;
  /** @deprecated */
  options: $low_request.RequestOptions$;
  /** @deprecated */
  timeout: $connection.Timeout$;
}

export type Request$ = Request;

export class RequestFields extends _.CustomType {
  /** @deprecated */
  constructor(
    method: $low_request.Method$,
    path: string,
    headers: _.List<[string, string]>,
    body: _.BitArray,
    options: $low_request.RequestOptions$,
    timeout: $connection.Timeout$
  );
  /** @deprecated */
  method: $low_request.Method$;
  /** @deprecated */
  path: string;
  /** @deprecated */
  headers: _.List<[string, string]>;
  /** @deprecated */
  body: _.BitArray;
  /** @deprecated */
  options: $low_request.RequestOptions$;
  /** @deprecated */
  timeout: $connection.Timeout$;
}
export function RequestFields$RequestFields(
  method: $low_request.Method$,
  path: string,
  headers: _.List<[string, string]>,
  body: _.BitArray,
  options: $low_request.RequestOptions$,
  timeout: $connection.Timeout$,
): RequestFields$;
export function RequestFields$isRequestFields(
  value: any,
): value is RequestFields$;
export function RequestFields$RequestFields$0(value: RequestFields$): $low_request.Method$;
export function RequestFields$RequestFields$method(
  value: RequestFields$,
): $low_request.Method$;
export function RequestFields$RequestFields$1(value: RequestFields$): string;
export function RequestFields$RequestFields$path(value: RequestFields$): string;
export function RequestFields$RequestFields$2(value: RequestFields$): _.List<
  [string, string]
>;
export function RequestFields$RequestFields$headers(value: RequestFields$): _.List<
  [string, string]
>;
export function RequestFields$RequestFields$3(value: RequestFields$): _.BitArray;
export function RequestFields$RequestFields$body(
  value: RequestFields$,
): _.BitArray;
export function RequestFields$RequestFields$4(value: RequestFields$): $low_request.RequestOptions$;
export function RequestFields$RequestFields$options(
  value: RequestFields$,
): $low_request.RequestOptions$;
export function RequestFields$RequestFields$5(value: RequestFields$): $connection.Timeout$;
export function RequestFields$RequestFields$timeout(
  value: RequestFields$,
): $connection.Timeout$;

export type RequestFields$ = RequestFields;

declare class AwaitingResponse extends _.CustomType {
  /** @deprecated */
  constructor(informational: _.List<[number, _.List<[string, string]>]>);
  /** @deprecated */
  informational: _.List<[number, _.List<[string, string]>]>;
}

declare class Collecting extends _.CustomType {
  /** @deprecated */
  constructor(
    status: number,
    headers: _.List<[string, string]>,
    chunks: _.List<_.BitArray>,
    trailers: _.List<[string, string]>,
    informational: _.List<[number, _.List<[string, string]>]>
  );
  /** @deprecated */
  status: number;
  /** @deprecated */
  headers: _.List<[string, string]>;
  /** @deprecated */
  chunks: _.List<_.BitArray>;
  /** @deprecated */
  trailers: _.List<[string, string]>;
  /** @deprecated */
  informational: _.List<[number, _.List<[string, string]>]>;
}

type Collection$ = AwaitingResponse | Collecting;

declare class Continue extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: Collection$);
  /** @deprecated */
  0: Collection$;
}

declare class Done extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $response.Response$);
  /** @deprecated */
  0: $response.Response$;
}

type Step$ = Continue | Done;

export function new$(method: $low_request.Method$, path: string): Request$;

export function with_header(request: Request$, name: string, value: string): Request$;

export function with_headers(
  request: Request$,
  headers: _.List<[string, string]>
): Request$;

export function with_body(request: Request$, body: _.BitArray): Request$;

export function with_options(
  request: Request$,
  options: $low_request.RequestOptions$
): Request$;

export function with_timeout(request: Request$, timeout: $connection.Timeout$): Request$;

export function inspect_request(request: Request$): RequestFields$;

export function request_with(
  connection: $internal.Connection$,
  method: $low_request.Method$,
  path: string,
  headers: _.List<[string, string]>,
  body: _.BitArray,
  options: $low_request.RequestOptions$,
  timeout: $connection.Timeout$,
  request_fn: (
    x0: $internal.Connection$,
    x1: $low_request.Method$,
    x2: string,
    x3: _.List<[string, string]>,
    x4: _.BitArray,
    x5: $low_request.RequestOptions$
  ) => _.Result<$internal.Stream$, $error.GluegunError$>,
  await_fn: (
    x0: $internal.Connection$,
    x1: $internal.Stream$,
    x2: $connection.Timeout$
  ) => _.Result<$message.Message$, $error.GluegunError$>
): _.Result<$response.Response$, $error.GluegunError$>;

export function send_raw(
  connection: $internal.Connection$,
  method: $low_request.Method$,
  path: string,
  headers: _.List<[string, string]>,
  body: _.BitArray,
  options: $low_request.RequestOptions$,
  timeout: $connection.Timeout$
): _.Result<$response.Response$, $error.GluegunError$>;

export function send(request: Request$, connection: $internal.Connection$): _.Result<
  $response.Response$,
  $error.GluegunError$
>;

export function get(
  connection: $internal.Connection$,
  path: string,
  headers: _.List<[string, string]>,
  timeout: $connection.Timeout$
): _.Result<$response.Response$, $error.GluegunError$>;

export function post(
  connection: $internal.Connection$,
  path: string,
  headers: _.List<[string, string]>,
  body: _.BitArray,
  timeout: $connection.Timeout$
): _.Result<$response.Response$, $error.GluegunError$>;

export function put(
  connection: $internal.Connection$,
  path: string,
  headers: _.List<[string, string]>,
  body: _.BitArray,
  timeout: $connection.Timeout$
): _.Result<$response.Response$, $error.GluegunError$>;

export function patch(
  connection: $internal.Connection$,
  path: string,
  headers: _.List<[string, string]>,
  body: _.BitArray,
  timeout: $connection.Timeout$
): _.Result<$response.Response$, $error.GluegunError$>;

export function delete$(
  connection: $internal.Connection$,
  path: string,
  headers: _.List<[string, string]>,
  timeout: $connection.Timeout$
): _.Result<$response.Response$, $error.GluegunError$>;

export function head(
  connection: $internal.Connection$,
  path: string,
  headers: _.List<[string, string]>,
  timeout: $connection.Timeout$
): _.Result<$response.Response$, $error.GluegunError$>;

export function options(
  connection: $internal.Connection$,
  path: string,
  headers: _.List<[string, string]>,
  timeout: $connection.Timeout$
): _.Result<$response.Response$, $error.GluegunError$>;

export function collect_messages(
  messages: _.List<_.Result<$message.Message$, $error.GluegunError$>>
): _.Result<$response.Response$, $error.GluegunError$>;

export function get_with(
  connection: $internal.Connection$,
  path: string,
  headers: _.List<[string, string]>,
  timeout: $connection.Timeout$,
  request_fn: (
    x0: $internal.Connection$,
    x1: $low_request.Method$,
    x2: string,
    x3: _.List<[string, string]>,
    x4: _.BitArray,
    x5: $low_request.RequestOptions$
  ) => _.Result<$internal.Stream$, $error.GluegunError$>,
  await_fn: (
    x0: $internal.Connection$,
    x1: $internal.Stream$,
    x2: $connection.Timeout$
  ) => _.Result<$message.Message$, $error.GluegunError$>
): _.Result<$response.Response$, $error.GluegunError$>;
