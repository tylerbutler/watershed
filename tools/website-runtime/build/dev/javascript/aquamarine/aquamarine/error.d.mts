import type * as $codec from "../aquamarine/codec.d.mts";
import type * as _ from "../gleam.d.mts";

export class Timeout extends _.CustomType {}
export function TransportError$Timeout(): TransportError$;
export function TransportError$isTimeout(value: any): value is TransportError$;

export class ConnectionDown extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function TransportError$ConnectionDown(reason: string): TransportError$;
export function TransportError$isConnectionDown(
  value: any,
): value is TransportError$;
export function TransportError$ConnectionDown$0(value: TransportError$): string;
export function TransportError$ConnectionDown$reason(value: TransportError$): string;

export class ConnectionError extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function TransportError$ConnectionError(reason: string): TransportError$;
export function TransportError$isConnectionError(
  value: any,
): value is TransportError$;
export function TransportError$ConnectionError$0(value: TransportError$): string;
export function TransportError$ConnectionError$reason(
  value: TransportError$,
): string;

export class StreamError extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function TransportError$StreamError(reason: string): TransportError$;
export function TransportError$isStreamError(
  value: any,
): value is TransportError$;
export function TransportError$StreamError$0(value: TransportError$): string;
export function TransportError$StreamError$reason(value: TransportError$): string;

export class InvalidOptions extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function TransportError$InvalidOptions(reason: string): TransportError$;
export function TransportError$isInvalidOptions(
  value: any,
): value is TransportError$;
export function TransportError$InvalidOptions$0(value: TransportError$): string;
export function TransportError$InvalidOptions$reason(value: TransportError$): string;

export class InvalidMessage extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function TransportError$InvalidMessage(reason: string): TransportError$;
export function TransportError$isInvalidMessage(
  value: any,
): value is TransportError$;
export function TransportError$InvalidMessage$0(value: TransportError$): string;
export function TransportError$InvalidMessage$reason(value: TransportError$): string;

export class ErlangError extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function TransportError$ErlangError(reason: string): TransportError$;
export function TransportError$isErlangError(
  value: any,
): value is TransportError$;
export function TransportError$ErlangError$0(value: TransportError$): string;
export function TransportError$ErlangError$reason(value: TransportError$): string;

export class DecodeError extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function TransportError$DecodeError(reason: string): TransportError$;
export function TransportError$isDecodeError(
  value: any,
): value is TransportError$;
export function TransportError$DecodeError$0(value: TransportError$): string;
export function TransportError$DecodeError$reason(value: TransportError$): string;

export type TransportError$ = Timeout | ConnectionDown | ConnectionError | StreamError | InvalidOptions | InvalidMessage | ErlangError | DecodeError;

export class Transport extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: TransportError$);
  /** @deprecated */
  0: TransportError$;
}
export function AquamarineError$Transport(
  $0: TransportError$,
): AquamarineError$;
export function AquamarineError$isTransport(
  value: any,
): value is AquamarineError$;
export function AquamarineError$Transport$0(value: AquamarineError$): TransportError$;

export class JoinRejected extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function AquamarineError$JoinRejected(reason: string): AquamarineError$;
export function AquamarineError$isJoinRejected(
  value: any,
): value is AquamarineError$;
export function AquamarineError$JoinRejected$0(value: AquamarineError$): string;
export function AquamarineError$JoinRejected$reason(value: AquamarineError$): string;

export class ChannelClosed extends _.CustomType {}
export function AquamarineError$ChannelClosed(): AquamarineError$;
export function AquamarineError$isChannelClosed(
  value: any,
): value is AquamarineError$;

export class DecodeFailed extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $codec.DecodeError$);
  /** @deprecated */
  0: $codec.DecodeError$;
}
export function AquamarineError$DecodeFailed(
  $0: $codec.DecodeError$,
): AquamarineError$;
export function AquamarineError$isDecodeFailed(
  value: any,
): value is AquamarineError$;
export function AquamarineError$DecodeFailed$0(value: AquamarineError$): $codec.DecodeError$;

export class ReplyTimeout extends _.CustomType {}
export function AquamarineError$ReplyTimeout(): AquamarineError$;
export function AquamarineError$isReplyTimeout(
  value: any,
): value is AquamarineError$;

export class InternalError extends _.CustomType {
  /** @deprecated */
  constructor(reason: string);
  /** @deprecated */
  reason: string;
}
export function AquamarineError$InternalError(reason: string): AquamarineError$;
export function AquamarineError$isInternalError(
  value: any,
): value is AquamarineError$;
export function AquamarineError$InternalError$0(value: AquamarineError$): string;
export function AquamarineError$InternalError$reason(
  value: AquamarineError$,
): string;

export type AquamarineError$ = Transport | JoinRejected | ChannelClosed | DecodeFailed | ReplyTimeout | InternalError;
