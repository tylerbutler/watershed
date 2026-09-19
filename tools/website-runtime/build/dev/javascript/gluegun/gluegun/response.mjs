/// <reference types="./response.d.mts" />
import * as $bit_array from "../../gleam_stdlib/gleam/bit_array.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import { List$Empty$const as $List$Empty$const, CustomType as $CustomType } from "../gleam.mjs";
import * as $error from "../gluegun/error.mjs";
import * as $request from "../gluegun/request.mjs";

class Response extends $CustomType {
  constructor(status, headers, body, trailers, informational) {
    super();
    this.status = status;
    this.headers = headers;
    this.body = body;
    this.trailers = trailers;
    this.informational = informational;
  }
}

/**
 * Return the final response status.
 */
export function status(response) {
  return response.status;
}

/**
 * Return final response headers.
 */
export function headers(response) {
  return response.headers;
}

/**
 * Return the full collected response body.
 */
export function body(response) {
  return response.body;
}

/**
 * Return response trailers.
 */
export function trailers(response) {
  return response.trailers;
}

/**
 * Return informational `1xx` responses received before the final response.
 */
export function informational(response) {
  return response.informational;
}

/**
 * Construct a response without informational responses.
 */
export function new$(status, headers, body, trailers) {
  return new Response(status, headers, body, trailers, $List$Empty$const);
}

/**
 * Return a response with a replaced body.
 */
export function with_body(response, body) {
  return new Response(
    response.status,
    response.headers,
    body,
    response.trailers,
    response.informational,
  );
}

/**
 * Return a response with replaced trailers.
 */
export function with_trailers(response, trailers) {
  return new Response(
    response.status,
    response.headers,
    response.body,
    trailers,
    response.informational,
  );
}

/**
 * Return a response with replaced informational responses.
 */
export function with_informational(response, informational) {
  return new Response(
    response.status,
    response.headers,
    response.body,
    response.trailers,
    informational,
  );
}

/**
 * Decode a response body as UTF-8 text.
 */
export function body_text(response) {
  let _pipe = response.body;
  let _pipe$1 = $bit_array.to_string(_pipe);
  return $result.map_error(
    _pipe$1,
    (_) => { return new $error.DecodeError("Response body is not valid UTF-8"); },
  );
}
