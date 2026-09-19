import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "../gleam.d.mts";

export class Timeout extends _.CustomType {}
export function GluegunError$Timeout(): GluegunError$;
export function GluegunError$isTimeout(value: any): value is GluegunError$;

export class ConnectionDown extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function GluegunError$ConnectionDown($0: string): GluegunError$;
export function GluegunError$isConnectionDown(
  value: any,
): value is GluegunError$;
export function GluegunError$ConnectionDown$0(value: GluegunError$): string;

export class ConnectionError extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function GluegunError$ConnectionError($0: string): GluegunError$;
export function GluegunError$isConnectionError(
  value: any,
): value is GluegunError$;
export function GluegunError$ConnectionError$0(value: GluegunError$): string;

export class StreamError extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function GluegunError$StreamError($0: string): GluegunError$;
export function GluegunError$isStreamError(value: any): value is GluegunError$;
export function GluegunError$StreamError$0(value: GluegunError$): string;

export class InvalidOptions extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function GluegunError$InvalidOptions($0: string): GluegunError$;
export function GluegunError$isInvalidOptions(
  value: any,
): value is GluegunError$;
export function GluegunError$InvalidOptions$0(value: GluegunError$): string;

export class InvalidMessage extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function GluegunError$InvalidMessage($0: string): GluegunError$;
export function GluegunError$isInvalidMessage(
  value: any,
): value is GluegunError$;
export function GluegunError$InvalidMessage$0(value: GluegunError$): string;

export class ErlangError extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function GluegunError$ErlangError($0: string): GluegunError$;
export function GluegunError$isErlangError(value: any): value is GluegunError$;
export function GluegunError$ErlangError$0(value: GluegunError$): string;

export class DecodeError extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function GluegunError$DecodeError($0: string): GluegunError$;
export function GluegunError$isDecodeError(value: any): value is GluegunError$;
export function GluegunError$DecodeError$0(value: GluegunError$): string;

export type GluegunError$ = Timeout | ConnectionDown | ConnectionError | StreamError | InvalidOptions | InvalidMessage | ErlangError | DecodeError;

export function decode_ffi_error(error: $dynamic.Dynamic$): GluegunError$;
