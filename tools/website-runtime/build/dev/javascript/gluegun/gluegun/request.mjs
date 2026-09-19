/// <reference types="./request.d.mts" />
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { List$Empty$const as $List$Empty$const, CustomType as $CustomType } from "../gleam.mjs";
import * as $error from "../gluegun/error.mjs";
import * as $fin from "../gluegun/fin.mjs";
import * as $internal from "../gluegun/internal.mjs";
import * as $ffi_result from "../gluegun/internal/ffi_result.mjs";

export class Get extends $CustomType {}
export const Method$Get$const = new Get();
export const Method$Get = () => Method$Get$const;
export const Method$isGet = (value) => value instanceof Get;

export class Head extends $CustomType {}
export const Method$Head$const = new Head();
export const Method$Head = () => Method$Head$const;
export const Method$isHead = (value) => value instanceof Head;

export class Post extends $CustomType {}
export const Method$Post$const = new Post();
export const Method$Post = () => Method$Post$const;
export const Method$isPost = (value) => value instanceof Post;

export class Put extends $CustomType {}
export const Method$Put$const = new Put();
export const Method$Put = () => Method$Put$const;
export const Method$isPut = (value) => value instanceof Put;

export class Patch extends $CustomType {}
export const Method$Patch$const = new Patch();
export const Method$Patch = () => Method$Patch$const;
export const Method$isPatch = (value) => value instanceof Patch;

export class Delete extends $CustomType {}
export const Method$Delete$const = new Delete();
export const Method$Delete = () => Method$Delete$const;
export const Method$isDelete = (value) => value instanceof Delete;

export class Options extends $CustomType {}
export const Method$Options$const = new Options();
export const Method$Options = () => Method$Options$const;
export const Method$isOptions = (value) => value instanceof Options;

export class Trace extends $CustomType {}
export const Method$Trace$const = new Trace();
export const Method$Trace = () => Method$Trace$const;
export const Method$isTrace = (value) => value instanceof Trace;

export class Connect extends $CustomType {}
export const Method$Connect$const = new Connect();
export const Method$Connect = () => Method$Connect$const;
export const Method$isConnect = (value) => value instanceof Connect;

export class Custom extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const Method$Custom = ($0) => new Custom($0);
export const Method$isCustom = (value) => value instanceof Custom;
export const Method$Custom$0 = (value) => value[0];

class RequestOptions extends $CustomType {
  constructor(headers, reserved) {
    super();
    this.headers = headers;
    this.reserved = reserved;
  }
}

/**
 * Construct default request options.
 */
export function options() {
  return new RequestOptions($List$Empty$const, undefined);
}

/**
 * Add option-level headers that are appended to per-call headers.
 */
export function with_headers(options, headers) {
  return new RequestOptions(
    $list.append(options.headers, headers),
    options.reserved,
  );
}

/**
 * Replace option-level headers.
 */
export function set_headers(options, headers) {
  return new RequestOptions(headers, options.reserved);
}

/**
 * Inspect option-level headers.
 * 
 * @ignore
 */
export function headers_option(options) {
  return options.headers;
}

/**
 * Convert a method constructor to its HTTP method string.
 */
export function method_to_string(method) {
  if (method instanceof Get) {
    return "GET";
  } else if (method instanceof Head) {
    return "HEAD";
  } else if (method instanceof Post) {
    return "POST";
  } else if (method instanceof Put) {
    return "PUT";
  } else if (method instanceof Patch) {
    return "PATCH";
  } else if (method instanceof Delete) {
    return "DELETE";
  } else if (method instanceof Options) {
    return "OPTIONS";
  } else if (method instanceof Trace) {
    return "TRACE";
  } else if (method instanceof Connect) {
    return "CONNECT";
  } else {
    let method$1 = method[0];
    return method$1;
  }
}

/**
 * Lowercase header names for the Erlang Gun FFI boundary without changing values.
 */
export function normalize_headers(headers) {
  return $list.map(
    headers,
    (header) => {
      let name = header[0];
      let value = header[1];
      return [$string.lowercase(name), value];
    },
  );
}

function options_to_ffi(_) {
  return $dynamic.properties($List$Empty$const);
}

export function headers_args_to_ffi(method, path, headers, options) {
  return [
    method_to_string(method),
    path,
    normalize_headers($list.append(headers, options.headers)),
    options_to_ffi(options),
  ];
}

export function update_flow_args_to_ffi(connection, stream, increment) {
  return [
    $internal.connection_raw(connection),
    $internal.stream_raw(stream),
    increment,
  ];
}
