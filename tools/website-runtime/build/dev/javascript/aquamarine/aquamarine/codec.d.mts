import type * as $json from "../../gleam_json/gleam/json.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
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

export class Codec extends _.CustomType {
  /** @deprecated */
  constructor(
    decode: (x0: string) => _.Result<Incoming$, DecodeError$>,
    encode_join: (x0: string, x1: string, x2: $json.Json$) => string,
    encode_push: (
      x0: string,
      x1: string,
      x2: string,
      x3: string,
      x4: $json.Json$
    ) => string,
    encode_heartbeat: (x0: string) => string,
    matches_reply: (x0: Incoming$, x1: string) => boolean,
    reply_status: (x0: Incoming$) => _.Result<undefined, string>,
    join_event: string,
    reply_event: string,
    close_event: string,
    error_event: string,
    heartbeat_topic: string
  );
  /** @deprecated */
  decode: (x0: string) => _.Result<Incoming$, DecodeError$>;
  /** @deprecated */
  encode_join: (x0: string, x1: string, x2: $json.Json$) => string;
  /** @deprecated */
  encode_push: (x0: string, x1: string, x2: string, x3: string, x4: $json.Json$) => string;
  /** @deprecated */
  encode_heartbeat: (x0: string) => string;
  /** @deprecated */
  matches_reply: (x0: Incoming$, x1: string) => boolean;
  /** @deprecated */
  reply_status: (x0: Incoming$) => _.Result<undefined, string>;
  /** @deprecated */
  join_event: string;
  /** @deprecated */
  reply_event: string;
  /** @deprecated */
  close_event: string;
  /** @deprecated */
  error_event: string;
  /** @deprecated */
  heartbeat_topic: string;
}
export function Codec$Codec(
  decode: (x0: string) => _.Result<Incoming$, DecodeError$>,
  encode_join: (x0: string, x1: string, x2: $json.Json$) => string,
  encode_push: (x0: string, x1: string, x2: string, x3: string, x4: $json.Json$) => string,
  encode_heartbeat: (x0: string) => string,
  matches_reply: (x0: Incoming$, x1: string) => boolean,
  reply_status: (x0: Incoming$) => _.Result<undefined, string>,
  join_event: string,
  reply_event: string,
  close_event: string,
  error_event: string,
  heartbeat_topic: string,
): Codec$;
export function Codec$isCodec(value: any): value is Codec$;
export function Codec$Codec$0(value: Codec$): (x0: string) => _.Result<
  Incoming$,
  DecodeError$
>;
export function Codec$Codec$decode(value: Codec$): (x0: string) => _.Result<
  Incoming$,
  DecodeError$
>;
export function Codec$Codec$1(value: Codec$): (
  x0: string,
  x1: string,
  x2: $json.Json$
) => string;
export function Codec$Codec$encode_join(value: Codec$): (
  x0: string,
  x1: string,
  x2: $json.Json$
) => string;
export function Codec$Codec$2(value: Codec$): (
  x0: string,
  x1: string,
  x2: string,
  x3: string,
  x4: $json.Json$
) => string;
export function Codec$Codec$encode_push(value: Codec$): (
  x0: string,
  x1: string,
  x2: string,
  x3: string,
  x4: $json.Json$
) => string;
export function Codec$Codec$3(value: Codec$): (x0: string) => string;
export function Codec$Codec$encode_heartbeat(value: Codec$): (x0: string) => string;
export function Codec$Codec$4(
  value: Codec$,
): (x0: Incoming$, x1: string) => boolean;
export function Codec$Codec$matches_reply(value: Codec$): (
  x0: Incoming$,
  x1: string
) => boolean;
export function Codec$Codec$5(value: Codec$): (x0: Incoming$) => _.Result<
  undefined,
  string
>;
export function Codec$Codec$reply_status(value: Codec$): (x0: Incoming$) => _.Result<
  undefined,
  string
>;
export function Codec$Codec$6(value: Codec$): string;
export function Codec$Codec$join_event(value: Codec$): string;
export function Codec$Codec$7(value: Codec$): string;
export function Codec$Codec$reply_event(value: Codec$): string;
export function Codec$Codec$8(value: Codec$): string;
export function Codec$Codec$close_event(value: Codec$): string;
export function Codec$Codec$9(value: Codec$): string;
export function Codec$Codec$error_event(value: Codec$): string;
export function Codec$Codec$10(value: Codec$): string;
export function Codec$Codec$heartbeat_topic(value: Codec$): string;

export type Codec$ = Codec;
