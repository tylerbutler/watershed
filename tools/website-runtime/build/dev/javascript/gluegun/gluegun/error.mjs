/// <reference types="./error.d.mts" />
import * as $atom from "../../gleam_erlang/gleam/erlang/atom.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $dyn_decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";

export class Timeout extends $CustomType {}
export const GluegunError$Timeout$const = new Timeout();
export const GluegunError$Timeout = () => GluegunError$Timeout$const;
export const GluegunError$isTimeout = (value) => value instanceof Timeout;

export class ConnectionDown extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const GluegunError$ConnectionDown = ($0) => new ConnectionDown($0);
export const GluegunError$isConnectionDown = (value) =>
  value instanceof ConnectionDown;
export const GluegunError$ConnectionDown$0 = (value) => value[0];

export class ConnectionError extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const GluegunError$ConnectionError = ($0) => new ConnectionError($0);
export const GluegunError$isConnectionError = (value) =>
  value instanceof ConnectionError;
export const GluegunError$ConnectionError$0 = (value) => value[0];

export class StreamError extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const GluegunError$StreamError = ($0) => new StreamError($0);
export const GluegunError$isStreamError = (value) =>
  value instanceof StreamError;
export const GluegunError$StreamError$0 = (value) => value[0];

export class InvalidOptions extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const GluegunError$InvalidOptions = ($0) => new InvalidOptions($0);
export const GluegunError$isInvalidOptions = (value) =>
  value instanceof InvalidOptions;
export const GluegunError$InvalidOptions$0 = (value) => value[0];

export class InvalidMessage extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const GluegunError$InvalidMessage = ($0) => new InvalidMessage($0);
export const GluegunError$isInvalidMessage = (value) =>
  value instanceof InvalidMessage;
export const GluegunError$InvalidMessage$0 = (value) => value[0];

export class ErlangError extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const GluegunError$ErlangError = ($0) => new ErlangError($0);
export const GluegunError$isErlangError = (value) =>
  value instanceof ErlangError;
export const GluegunError$ErlangError$0 = (value) => value[0];

export class DecodeError extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const GluegunError$DecodeError = ($0) => new DecodeError($0);
export const GluegunError$isDecodeError = (value) =>
  value instanceof DecodeError;
export const GluegunError$DecodeError$0 = (value) => value[0];
