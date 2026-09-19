import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $connection from "../gluegun/connection.d.mts";
import type * as $error from "../gluegun/error.d.mts";
import type * as $fin from "../gluegun/fin.d.mts";
import type * as $internal from "../gluegun/internal.d.mts";
import type * as $request from "../gluegun/request.d.mts";

export class Text extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function Frame$Text($0: string): Frame$;
export function Frame$isText(value: any): value is Frame$;
export function Frame$Text$0(value: Frame$): string;

export class Binary extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.BitArray);
  /** @deprecated */
  0: _.BitArray;
}
export function Frame$Binary($0: _.BitArray): Frame$;
export function Frame$isBinary(value: any): value is Frame$;
export function Frame$Binary$0(value: Frame$): _.BitArray;

export class Ping extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.BitArray);
  /** @deprecated */
  0: _.BitArray;
}
export function Frame$Ping($0: _.BitArray): Frame$;
export function Frame$isPing(value: any): value is Frame$;
export function Frame$Ping$0(value: Frame$): _.BitArray;

export class Pong extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.BitArray);
  /** @deprecated */
  0: _.BitArray;
}
export function Frame$Pong($0: _.BitArray): Frame$;
export function Frame$isPong(value: any): value is Frame$;
export function Frame$Pong$0(value: Frame$): _.BitArray;

export class Close extends _.CustomType {}
export function Frame$Close(): Frame$;
export function Frame$isClose(value: any): value is Frame$;

export class CloseWithReason extends _.CustomType {
  /** @deprecated */
  constructor(code: number, reason: _.BitArray);
  /** @deprecated */
  code: number;
  /** @deprecated */
  reason: _.BitArray;
}
export function Frame$CloseWithReason(code: number, reason: _.BitArray): Frame$;
export function Frame$isCloseWithReason(value: any): value is Frame$;
export function Frame$CloseWithReason$0(value: Frame$): number;
export function Frame$CloseWithReason$code(value: Frame$): number;
export function Frame$CloseWithReason$1(value: Frame$): _.BitArray;
export function Frame$CloseWithReason$reason(value: Frame$): _.BitArray;

export type Frame$ = Text | Binary | Ping | Pong | Close | CloseWithReason;

export class Inform extends _.CustomType {
  /** @deprecated */
  constructor(status: number, headers: _.List<[string, string]>);
  /** @deprecated */
  status: number;
  /** @deprecated */
  headers: _.List<[string, string]>;
}
export function Message$Inform(
  status: number,
  headers: _.List<[string, string]>,
): Message$;
export function Message$isInform(value: any): value is Message$;
export function Message$Inform$0(value: Message$): number;
export function Message$Inform$status(value: Message$): number;
export function Message$Inform$1(value: Message$): _.List<[string, string]>;
export function Message$Inform$headers(value: Message$): _.List<
  [string, string]
>;

export class Response extends _.CustomType {
  /** @deprecated */
  constructor(fin: $fin.Fin$, status: number, headers: _.List<[string, string]>);
  /** @deprecated */
  fin: $fin.Fin$;
  /** @deprecated */
  status: number;
  /** @deprecated */
  headers: _.List<[string, string]>;
}
export function Message$Response(
  fin: $fin.Fin$,
  status: number,
  headers: _.List<[string, string]>,
): Message$;
export function Message$isResponse(value: any): value is Message$;
export function Message$Response$0(value: Message$): $fin.Fin$;
export function Message$Response$fin(value: Message$): $fin.Fin$;
export function Message$Response$1(value: Message$): number;
export function Message$Response$status(value: Message$): number;
export function Message$Response$2(value: Message$): _.List<[string, string]>;
export function Message$Response$headers(value: Message$): _.List<
  [string, string]
>;

export class Data extends _.CustomType {
  /** @deprecated */
  constructor(fin: $fin.Fin$, data: _.BitArray);
  /** @deprecated */
  fin: $fin.Fin$;
  /** @deprecated */
  data: _.BitArray;
}
export function Message$Data(fin: $fin.Fin$, data: _.BitArray): Message$;
export function Message$isData(value: any): value is Message$;
export function Message$Data$0(value: Message$): $fin.Fin$;
export function Message$Data$fin(value: Message$): $fin.Fin$;
export function Message$Data$1(value: Message$): _.BitArray;
export function Message$Data$data(value: Message$): _.BitArray;

export class Trailers extends _.CustomType {
  /** @deprecated */
  constructor(headers: _.List<[string, string]>);
  /** @deprecated */
  headers: _.List<[string, string]>;
}
export function Message$Trailers(headers: _.List<[string, string]>): Message$;
export function Message$isTrailers(value: any): value is Message$;
export function Message$Trailers$0(value: Message$): _.List<[string, string]>;
export function Message$Trailers$headers(value: Message$): _.List<
  [string, string]
>;

export class Push extends _.CustomType {
  /** @deprecated */
  constructor(
    stream: $internal.Stream$,
    method: $request.Method$,
    uri: string,
    headers: _.List<[string, string]>
  );
  /** @deprecated */
  stream: $internal.Stream$;
  /** @deprecated */
  method: $request.Method$;
  /** @deprecated */
  uri: string;
  /** @deprecated */
  headers: _.List<[string, string]>;
}
export function Message$Push(
  stream: $internal.Stream$,
  method: $request.Method$,
  uri: string,
  headers: _.List<[string, string]>,
): Message$;
export function Message$isPush(value: any): value is Message$;
export function Message$Push$0(value: Message$): $internal.Stream$;
export function Message$Push$stream(value: Message$): $internal.Stream$;
export function Message$Push$1(value: Message$): $request.Method$;
export function Message$Push$method(value: Message$): $request.Method$;
export function Message$Push$2(value: Message$): string;
export function Message$Push$uri(value: Message$): string;
export function Message$Push$3(value: Message$): _.List<[string, string]>;
export function Message$Push$headers(value: Message$): _.List<[string, string]>;

export class Upgrade extends _.CustomType {
  /** @deprecated */
  constructor(protocols: _.List<string>, headers: _.List<[string, string]>);
  /** @deprecated */
  protocols: _.List<string>;
  /** @deprecated */
  headers: _.List<[string, string]>;
}
export function Message$Upgrade(
  protocols: _.List<string>,
  headers: _.List<[string, string]>,
): Message$;
export function Message$isUpgrade(value: any): value is Message$;
export function Message$Upgrade$0(value: Message$): _.List<string>;
export function Message$Upgrade$protocols(value: Message$): _.List<string>;
export function Message$Upgrade$1(value: Message$): _.List<[string, string]>;
export function Message$Upgrade$headers(value: Message$): _.List<
  [string, string]
>;

export class WebSocket extends _.CustomType {
  /** @deprecated */
  constructor(frame: Frame$);
  /** @deprecated */
  frame: Frame$;
}
export function Message$WebSocket(frame: Frame$): Message$;
export function Message$isWebSocket(value: any): value is Message$;
export function Message$WebSocket$0(value: Message$): Frame$;
export function Message$WebSocket$frame(value: Message$): Frame$;

export type Message$ = Inform | Response | Data | Trailers | Push | Upgrade | WebSocket;

export type Method = $request.Method$;

export type Header = [string, string];

export type GluegunError = $error.GluegunError$;

export function decode(data: $dynamic.Dynamic$): _.Result<
  Message$,
  $error.GluegunError$
>;

export function decode_ffi_error(error: $dynamic.Dynamic$): $error.GluegunError$;

export function await$(
  connection: $internal.Connection$,
  stream: $internal.Stream$,
  timeout: $connection.Timeout$
): _.Result<Message$, $error.GluegunError$>;

export function await_body(
  connection: $internal.Connection$,
  stream: $internal.Stream$,
  timeout: $connection.Timeout$
): _.Result<_.BitArray, $error.GluegunError$>;
