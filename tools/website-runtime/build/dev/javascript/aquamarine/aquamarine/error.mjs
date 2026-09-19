/// <reference types="./error.d.mts" />
import * as $codec from "../aquamarine/codec.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";

export class Timeout extends $CustomType {}
export const TransportError$Timeout$const = new Timeout();
export const TransportError$Timeout = () => TransportError$Timeout$const;
export const TransportError$isTimeout = (value) => value instanceof Timeout;

export class ConnectionDown extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const TransportError$ConnectionDown = (reason) =>
  new ConnectionDown(reason);
export const TransportError$isConnectionDown = (value) =>
  value instanceof ConnectionDown;
export const TransportError$ConnectionDown$reason = (value) => value.reason;
export const TransportError$ConnectionDown$0 = (value) => value.reason;

export class ConnectionError extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const TransportError$ConnectionError = (reason) =>
  new ConnectionError(reason);
export const TransportError$isConnectionError = (value) =>
  value instanceof ConnectionError;
export const TransportError$ConnectionError$reason = (value) => value.reason;
export const TransportError$ConnectionError$0 = (value) => value.reason;

export class StreamError extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const TransportError$StreamError = (reason) => new StreamError(reason);
export const TransportError$isStreamError = (value) =>
  value instanceof StreamError;
export const TransportError$StreamError$reason = (value) => value.reason;
export const TransportError$StreamError$0 = (value) => value.reason;

export class InvalidOptions extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const TransportError$InvalidOptions = (reason) =>
  new InvalidOptions(reason);
export const TransportError$isInvalidOptions = (value) =>
  value instanceof InvalidOptions;
export const TransportError$InvalidOptions$reason = (value) => value.reason;
export const TransportError$InvalidOptions$0 = (value) => value.reason;

export class InvalidMessage extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const TransportError$InvalidMessage = (reason) =>
  new InvalidMessage(reason);
export const TransportError$isInvalidMessage = (value) =>
  value instanceof InvalidMessage;
export const TransportError$InvalidMessage$reason = (value) => value.reason;
export const TransportError$InvalidMessage$0 = (value) => value.reason;

export class ErlangError extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const TransportError$ErlangError = (reason) => new ErlangError(reason);
export const TransportError$isErlangError = (value) =>
  value instanceof ErlangError;
export const TransportError$ErlangError$reason = (value) => value.reason;
export const TransportError$ErlangError$0 = (value) => value.reason;

export class DecodeError extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const TransportError$DecodeError = (reason) => new DecodeError(reason);
export const TransportError$isDecodeError = (value) =>
  value instanceof DecodeError;
export const TransportError$DecodeError$reason = (value) => value.reason;
export const TransportError$DecodeError$0 = (value) => value.reason;

/**
 * Underlying WebSocket transport failure (connect, send, receive, close).
 */
export class Transport extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const AquamarineError$Transport = ($0) => new Transport($0);
export const AquamarineError$isTransport = (value) =>
  value instanceof Transport;
export const AquamarineError$Transport$0 = (value) => value[0];

/**
 * The server rejected the join with the given reason.
 */
export class JoinRejected extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const AquamarineError$JoinRejected = (reason) =>
  new JoinRejected(reason);
export const AquamarineError$isJoinRejected = (value) =>
  value instanceof JoinRejected;
export const AquamarineError$JoinRejected$reason = (value) => value.reason;
export const AquamarineError$JoinRejected$0 = (value) => value.reason;

/**
 * The server closed the channel.
 */
export class ChannelClosed extends $CustomType {}
export const AquamarineError$ChannelClosed$const = new ChannelClosed();
export const AquamarineError$ChannelClosed = () =>
  AquamarineError$ChannelClosed$const;
export const AquamarineError$isChannelClosed = (value) =>
  value instanceof ChannelClosed;

/**
 * An inbound wire frame could not be decoded.
 */
export class DecodeFailed extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const AquamarineError$DecodeFailed = ($0) => new DecodeFailed($0);
export const AquamarineError$isDecodeFailed = (value) =>
  value instanceof DecodeFailed;
export const AquamarineError$DecodeFailed$0 = (value) => value[0];

/**
 * Waited for a reply matching an outbound ref but it never arrived within
 * the configured timeout.
 */
export class ReplyTimeout extends $CustomType {}
export const AquamarineError$ReplyTimeout$const = new ReplyTimeout();
export const AquamarineError$ReplyTimeout = () =>
  AquamarineError$ReplyTimeout$const;
export const AquamarineError$isReplyTimeout = (value) =>
  value instanceof ReplyTimeout;

/**
 * An internal actor or system failure (e.g. failing to start the ref
 * counter or heartbeat actor) prevented the channel from initializing.
 */
export class InternalError extends $CustomType {
  constructor(reason) {
    super();
    this.reason = reason;
  }
}
export const AquamarineError$InternalError = (reason) =>
  new InternalError(reason);
export const AquamarineError$isInternalError = (value) =>
  value instanceof InternalError;
export const AquamarineError$InternalError$reason = (value) => value.reason;
export const AquamarineError$InternalError$0 = (value) => value.reason;
