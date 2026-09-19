/// <reference types="./connection.d.mts" />
import * as $atom from "../../gleam_erlang/gleam/erlang/atom.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";
import * as $error from "../gluegun/error.mjs";
import * as $internal from "../gluegun/internal.mjs";

/**
 * Let Gun choose TLS for TLS ports and TCP otherwise.
 */
export class Auto extends $CustomType {}
export const Transport$Auto$const = new Auto();
export const Transport$Auto = () => Transport$Auto$const;
export const Transport$isAuto = (value) => value instanceof Auto;

export class Tcp extends $CustomType {}
export const Transport$Tcp$const = new Tcp();
export const Transport$Tcp = () => Transport$Tcp$const;
export const Transport$isTcp = (value) => value instanceof Tcp;

export class Tls extends $CustomType {}
export const Transport$Tls$const = new Tls();
export const Transport$Tls = () => Transport$Tls$const;
export const Transport$isTls = (value) => value instanceof Tls;

export class Http1 extends $CustomType {}
export const Protocol$Http1$const = new Http1();
export const Protocol$Http1 = () => Protocol$Http1$const;
export const Protocol$isHttp1 = (value) => value instanceof Http1;

export class Http2 extends $CustomType {}
export const Protocol$Http2$const = new Http2();
export const Protocol$Http2 = () => Protocol$Http2$const;
export const Protocol$isHttp2 = (value) => value instanceof Http2;

export class Milliseconds extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Timeout$Milliseconds = ($0) => new Milliseconds($0);
export const Timeout$isMilliseconds = (value) => value instanceof Milliseconds;
export const Timeout$Milliseconds$0 = (value) => value[0];

export class Infinity extends $CustomType {}
export const Timeout$Infinity$const = new Infinity();
export const Timeout$Infinity = () => Timeout$Infinity$const;
export const Timeout$isInfinity = (value) => value instanceof Infinity;

class ConnectOptions extends $CustomType {
  constructor(transport, protocols, retry, connect_timeout) {
    super();
    this.transport = transport;
    this.protocols = protocols;
    this.retry = retry;
    this.connect_timeout = connect_timeout;
  }
}

/**
 * Construct default connection options.
 */
export function options() {
  return new ConnectOptions(
    Transport$Auto$const,
    Option$None$const,
    new Milliseconds(5000),
    new Milliseconds(5000),
  );
}

/**
 * Set the transport Gun should use for a connection.
 */
export function with_transport(options, transport) {
  return new ConnectOptions(
    transport,
    options.protocols,
    options.retry,
    options.connect_timeout,
  );
}

/**
 * Set HTTP protocol preference ordering for a connection.
 *
 * The list order is preserved when options are passed to Gun.
 */
export function with_protocols(options, protocols) {
  return new ConnectOptions(
    options.transport,
    new Some(protocols),
    options.retry,
    options.connect_timeout,
  );
}

/**
 * Set Gun's retry timeout option.
 */
export function with_retry(options, retry) {
  return new ConnectOptions(
    options.transport,
    options.protocols,
    retry,
    options.connect_timeout,
  );
}

/**
 * Set Gun's connect timeout option.
 */
export function with_connect_timeout(options, timeout) {
  return new ConnectOptions(
    options.transport,
    options.protocols,
    options.retry,
    timeout,
  );
}

/**
 * Inspect configured transport. Intended for tests and later FFI conversion.
 */
export function transport(options) {
  return options.transport;
}

/**
 * Inspect explicitly configured protocol ordering, if any.
 */
export function protocols(options) {
  return options.protocols;
}

/**
 * Inspect retry duration.
 */
export function retry(options) {
  return options.retry;
}

/**
 * Inspect connect timeout duration.
 */
export function connect_timeout(options) {
  return options.connect_timeout;
}
