import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $connection from "../gluegun/connection.d.mts";
import type * as $error from "../gluegun/error.d.mts";
import type * as $internal from "../gluegun/internal.d.mts";
import type * as $message from "../gluegun/message.d.mts";

declare class Socket extends _.CustomType {
  /** @deprecated */
  constructor(
    connection: $internal.Connection$,
    stream: $internal.Stream$,
    timeout: $connection.Timeout$
  );
  /** @deprecated */
  connection: $internal.Connection$;
  /** @deprecated */
  stream: $internal.Stream$;
  /** @deprecated */
  timeout: $connection.Timeout$;
}

export type Socket$ = Socket;

declare class Options extends _.CustomType {
  /** @deprecated */
  constructor(
    connect_options: $connection.ConnectOptions$,
    headers: _.List<[string, string]>,
    upgrade_options: UpgradeOptions$,
    timeout: $connection.Timeout$
  );
  /** @deprecated */
  connect_options: $connection.ConnectOptions$;
  /** @deprecated */
  headers: _.List<[string, string]>;
  /** @deprecated */
  upgrade_options: UpgradeOptions$;
  /** @deprecated */
  timeout: $connection.Timeout$;
}

export type Options$ = Options;

declare class UpgradeOptions extends _.CustomType {
  /** @deprecated */
  constructor(
    closing_timeout: $option.Option$<$connection.Timeout$>,
    compress: $option.Option$<boolean>,
    default_protocol: $option.Option$<string>,
    flow: $option.Option$<number>,
    keepalive: $option.Option$<$connection.Timeout$>,
    protocols: _.List<[string, string]>,
    reply_to: $option.Option$<$dynamic.Dynamic$>,
    silence_pings: $option.Option$<boolean>,
    tunnel: $option.Option$<$dynamic.Dynamic$>,
    user_opts: $option.Option$<$dynamic.Dynamic$>
  );
  /** @deprecated */
  closing_timeout: $option.Option$<$connection.Timeout$>;
  /** @deprecated */
  compress: $option.Option$<boolean>;
  /** @deprecated */
  default_protocol: $option.Option$<string>;
  /** @deprecated */
  flow: $option.Option$<number>;
  /** @deprecated */
  keepalive: $option.Option$<$connection.Timeout$>;
  /** @deprecated */
  protocols: _.List<[string, string]>;
  /** @deprecated */
  reply_to: $option.Option$<$dynamic.Dynamic$>;
  /** @deprecated */
  silence_pings: $option.Option$<boolean>;
  /** @deprecated */
  tunnel: $option.Option$<$dynamic.Dynamic$>;
  /** @deprecated */
  user_opts: $option.Option$<$dynamic.Dynamic$>;
}

export type UpgradeOptions$ = UpgradeOptions;

export function socket(
  connection: $internal.Connection$,
  stream: $internal.Stream$,
  timeout: $connection.Timeout$
): Socket$;

export function upgrade_options(): UpgradeOptions$;

export function options(): Options$;

export function with_headers(
  options: Options$,
  headers: _.List<[string, string]>
): Options$;

export function with_connect_options(
  options: Options$,
  connect: $connection.ConnectOptions$
): Options$;

export function with_upgrade_options(
  options: Options$,
  upgrade: UpgradeOptions$
): Options$;

export function with_timeout(options: Options$, timeout: $connection.Timeout$): Options$;

export function options_headers(options: Options$): _.List<[string, string]>;

export function options_connect_options(options: Options$): $connection.ConnectOptions$;

export function options_upgrade_options(options: Options$): UpgradeOptions$;

export function options_timeout(options: Options$): $connection.Timeout$;

export function await_upgrade_from(
  message_result: _.Result<$message.Message$, $error.GluegunError$>
): _.Result<undefined, $error.GluegunError$>;

export function await_upgrade(
  connection: $internal.Connection$,
  stream: $internal.Stream$,
  timeout: $connection.Timeout$
): _.Result<undefined, $error.GluegunError$>;

export function upgrade_options_to_ffi(options: UpgradeOptions$): $dynamic.Dynamic$;

export function upgrade_with_options(
  connection: $internal.Connection$,
  path: string,
  headers: _.List<[string, string]>,
  options: UpgradeOptions$
): _.Result<$internal.Stream$, $error.GluegunError$>;

export function upgrade_with_protocol_and_options(
  connection: $internal.Connection$,
  protocol: $connection.Protocol$,
  path: string,
  headers: _.List<[string, string]>,
  options: UpgradeOptions$
): _.Result<$internal.Stream$, $error.GluegunError$>;

export function connect(
  host: string,
  port: number,
  path: string,
  options: Options$
): _.Result<Socket$, $error.GluegunError$>;

export function with_socket_result<GDC>(
  callback_result: _.Result<GDC, $error.GluegunError$>,
  close_frame_result: _.Result<undefined, $error.GluegunError$>,
  close_connection_result: _.Result<undefined, $error.GluegunError$>
): _.Result<GDC, $error.GluegunError$>;

export function send_many(
  connection: $internal.Connection$,
  stream: $internal.Stream$,
  frames: _.List<$message.Frame$>
): _.Result<undefined, $error.GluegunError$>;

export function send(
  connection: $internal.Connection$,
  stream: $internal.Stream$,
  frame: $message.Frame$
): _.Result<undefined, $error.GluegunError$>;

export function send_frame(socket: Socket$, frame: $message.Frame$): _.Result<
  undefined,
  $error.GluegunError$
>;

export function close(socket: Socket$): _.Result<
  undefined,
  $error.GluegunError$
>;

export function with_socket<GCX>(
  host: string,
  port: number,
  path: string,
  options: Options$,
  callback: (x0: Socket$) => _.Result<GCX, $error.GluegunError$>
): _.Result<GCX, $error.GluegunError$>;

export function with_closing_timeout(
  options: UpgradeOptions$,
  timeout: $connection.Timeout$
): UpgradeOptions$;

export function with_compress(options: UpgradeOptions$, enabled: boolean): UpgradeOptions$;

export function with_flow(options: UpgradeOptions$, initial_flow: number): UpgradeOptions$;

export function with_keepalive(
  options: UpgradeOptions$,
  timeout: $connection.Timeout$
): UpgradeOptions$;

export function with_silence_pings(options: UpgradeOptions$, enabled: boolean): UpgradeOptions$;

export function with_default_protocol_module(
  options: UpgradeOptions$,
  module_name: string
): UpgradeOptions$;

export function with_protocol_module(
  options: UpgradeOptions$,
  protocol: string,
  module_name: string
): UpgradeOptions$;

export function with_reply_to_dynamic(
  options: UpgradeOptions$,
  reply_to: $dynamic.Dynamic$
): UpgradeOptions$;

export function with_tunnel_dynamic(
  options: UpgradeOptions$,
  tunnel: $dynamic.Dynamic$
): UpgradeOptions$;

export function with_user_opts_dynamic(
  options: UpgradeOptions$,
  user_opts: $dynamic.Dynamic$
): UpgradeOptions$;

export function upgrade_with_protocol(
  connection: $internal.Connection$,
  protocol: $connection.Protocol$,
  path: string,
  headers: _.List<[string, string]>
): _.Result<$internal.Stream$, $error.GluegunError$>;

export function upgrade(
  connection: $internal.Connection$,
  path: string,
  headers: _.List<[string, string]>
): _.Result<$internal.Stream$, $error.GluegunError$>;

export function send_text(socket: Socket$, text: string): _.Result<
  undefined,
  $error.GluegunError$
>;

export function send_binary(socket: Socket$, data: _.BitArray): _.Result<
  undefined,
  $error.GluegunError$
>;

export function ping(socket: Socket$, data: _.BitArray): _.Result<
  undefined,
  $error.GluegunError$
>;

export function pong(socket: Socket$, data: _.BitArray): _.Result<
  undefined,
  $error.GluegunError$
>;

export function receive_from(
  message_result: _.Result<$message.Message$, $error.GluegunError$>
): _.Result<$message.Frame$, $error.GluegunError$>;

export function receive(
  connection: $internal.Connection$,
  stream: $internal.Stream$,
  timeout: $connection.Timeout$
): _.Result<$message.Frame$, $error.GluegunError$>;

export function receive_frame(socket: Socket$): _.Result<
  $message.Frame$,
  $error.GluegunError$
>;

export function receive_app_frame(socket: Socket$): _.Result<
  $message.Frame$,
  $error.GluegunError$
>;

export function receive_app_frame_from(
  frame_results: _.List<_.Result<$message.Frame$, $error.GluegunError$>>,
  send_pong: (x0: _.BitArray) => _.Result<undefined, $error.GluegunError$>
): _.Result<$message.Frame$, $error.GluegunError$>;
