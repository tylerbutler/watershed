import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class Incoming extends _.CustomType {
  /** @deprecated */
  constructor(
    join_ref: $option.Option$<string>,
    ref: $option.Option$<string>,
    topic: string,
    event: string,
    payload: $dynamic.Dynamic$
  );
  /** @deprecated */
  join_ref: $option.Option$<string>;
  /** @deprecated */
  ref: $option.Option$<string>;
  /** @deprecated */
  topic: string;
  /** @deprecated */
  event: string;
  /** @deprecated */
  payload: $dynamic.Dynamic$;
}
export function Incoming$Incoming(
  join_ref: $option.Option$<string>,
  ref: $option.Option$<string>,
  topic: string,
  event: string,
  payload: $dynamic.Dynamic$,
): Incoming$;
export function Incoming$isIncoming(value: any): value is Incoming$;
export function Incoming$Incoming$0(value: Incoming$): $option.Option$<string>;
export function Incoming$Incoming$join_ref(value: Incoming$): $option.Option$<
  string
>;
export function Incoming$Incoming$1(value: Incoming$): $option.Option$<string>;
export function Incoming$Incoming$ref(value: Incoming$): $option.Option$<string>;
export function Incoming$Incoming$2(
  value: Incoming$,
): string;
export function Incoming$Incoming$topic(value: Incoming$): string;
export function Incoming$Incoming$3(value: Incoming$): string;
export function Incoming$Incoming$event(value: Incoming$): string;
export function Incoming$Incoming$4(value: Incoming$): $dynamic.Dynamic$;
export function Incoming$Incoming$payload(value: Incoming$): $dynamic.Dynamic$;

export type Incoming$ = Incoming;

export class InvalidJson extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function DecodeError$InvalidJson(reason: string): DecodeError$;
export function DecodeError$isInvalidJson(value: any): value is DecodeError$;
export function DecodeError$InvalidJson$0(value: DecodeError$): string;
export function DecodeError$InvalidJson$reason(value: DecodeError$): string;

export class InvalidFormat extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function DecodeError$InvalidFormat(reason: string): DecodeError$;
export function DecodeError$isInvalidFormat(value: any): value is DecodeError$;
export function DecodeError$InvalidFormat$0(value: DecodeError$): string;
export function DecodeError$InvalidFormat$reason(value: DecodeError$): string;

export type DecodeError$ = InvalidJson | InvalidFormat;

export function DecodeError$reason(value: DecodeError$): string;

export class StatusOk extends _.CustomType {}
export function ReplyStatus$StatusOk(): ReplyStatus$;
export function ReplyStatus$isStatusOk(value: any): value is ReplyStatus$;

export class StatusError extends _.CustomType {}
export function ReplyStatus$StatusError(): ReplyStatus$;
export function ReplyStatus$isStatusError(value: any): value is ReplyStatus$;

export type ReplyStatus$ = StatusOk | StatusError;

export const heartbeat_event: string;

export const heartbeat_topic: string;

export const reply_event: string;

export const close_event: string;

export const error_event: string;

export const leave_event: string;

export const join_event: string;

export function encode(
  join_ref: $option.Option$<string>,
  ref: $option.Option$<string>,
  topic: string,
  event: string,
  payload: $json.Json$
): string;

export function encode_heartbeat(ref: string): string;

export function encode_reply(
  join_ref: $option.Option$<string>,
  ref: string,
  topic: string,
  status: ReplyStatus$,
  response: $json.Json$
): string;

export function decode(text: string): _.Result<Incoming$, DecodeError$>;

export function matches_join_reply(incoming: Incoming$, join_ref: string): boolean;

export function reply_status(incoming: Incoming$): _.Result<undefined, string>;

export function is_system_event(event: string): boolean;
