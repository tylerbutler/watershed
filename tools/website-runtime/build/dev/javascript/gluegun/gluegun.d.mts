import type * as _ from "./gleam.d.mts";
import type * as $client from "./gluegun/client.d.mts";
import type * as $connection from "./gluegun/connection.d.mts";
import type * as $error from "./gluegun/error.d.mts";
import type * as $internal from "./gluegun/internal.d.mts";
import type * as $message from "./gluegun/message.d.mts";
import type * as $request from "./gluegun/request.d.mts";
import type * as $response from "./gluegun/response.d.mts";
import type * as $websocket from "./gluegun/websocket.d.mts";

export function name(): string;

export function connection_options(): $connection.ConnectOptions$;

export function open(
  options: $connection.ConnectOptions$,
  host: string,
  port: number
): _.Result<$internal.Connection$, $error.GluegunError$>;

export function with_transport(
  options: $connection.ConnectOptions$,
  transport: $connection.Transport$
): $connection.ConnectOptions$;

export function with_protocols(
  options: $connection.ConnectOptions$,
  protocols: _.List<$connection.Protocol$>
): $connection.ConnectOptions$;

export function with_retry(
  options: $connection.ConnectOptions$,
  retry: $connection.Timeout$
): $connection.ConnectOptions$;

export function with_connect_timeout(
  options: $connection.ConnectOptions$,
  timeout: $connection.Timeout$
): $connection.ConnectOptions$;

export function method_to_string(method: $low_request.Method$): string;

export function normalize_headers(headers: _.List<[string, string]>): _.List<
  [string, string]
>;

export function response(
  status: number,
  headers: _.List<[string, string]>,
  body: _.BitArray,
  trailers: _.List<[string, string]>
): $http_response.Response$;

export function body_text(response: $http_response.Response$): _.Result<
  string,
  $error.GluegunError$
>;

export function request(method: $low_request.Method$, path: string): $http_client.Request$;

export function send(
  request: $http_client.Request$,
  connection: $internal.Connection$
): _.Result<$http_response.Response$, $error.GluegunError$>;

export function websocket_options(): $websocket.Options$;

export function websocket_connect(
  host: string,
  port: number,
  path: string,
  options: $websocket.Options$
): _.Result<$websocket.Socket$, $error.GluegunError$>;

export function websocket_with_socket<GNL>(
  host: string,
  port: number,
  path: string,
  options: $websocket.Options$,
  callback: (x0: $websocket.Socket$) => _.Result<GNL, $error.GluegunError$>
): _.Result<GNL, $error.GluegunError$>;

export function websocket_send_text(socket: $websocket.Socket$, text: string): _.Result<
  undefined,
  $error.GluegunError$
>;

export function websocket_receive_app_frame(socket: $websocket.Socket$): _.Result<
  $message.Frame$,
  $error.GluegunError$
>;

export function websocket_close(socket: $websocket.Socket$): _.Result<
  undefined,
  $error.GluegunError$
>;
