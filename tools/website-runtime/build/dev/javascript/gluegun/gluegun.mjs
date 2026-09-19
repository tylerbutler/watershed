/// <reference types="./gluegun.d.mts" />
import * as $http_client from "./gluegun/client.mjs";
import * as $connection from "./gluegun/connection.mjs";
import * as $error from "./gluegun/error.mjs";
import * as $internal from "./gluegun/internal.mjs";
import * as $message from "./gluegun/message.mjs";
import * as $low_request from "./gluegun/request.mjs";
import * as $http_response from "./gluegun/response.mjs";
import * as $websocket from "./gluegun/websocket.mjs";

/**
 * Return the package name.
 */
export function name() {
  return "gluegun";
}

/**
 * Construct default connection options.
 */
export function connection_options() {
  return $connection.options();
}

/**
 * Set the transport on connection options.
 */
export function with_transport(options, transport) {
  return $connection.with_transport(options, transport);
}

/**
 * Set protocol preferences on connection options.
 */
export function with_protocols(options, protocols) {
  return $connection.with_protocols(options, protocols);
}

/**
 * Set Gun retry timeout on connection options.
 */
export function with_retry(options, retry) {
  return $connection.with_retry(options, retry);
}

/**
 * Set connect timeout on connection options.
 */
export function with_connect_timeout(options, timeout) {
  return $connection.with_connect_timeout(options, timeout);
}

/**
 * Convert a request method to an HTTP method string.
 */
export function method_to_string(method) {
  return $low_request.method_to_string(method);
}

/**
 * Normalize header names for Gun.
 */
export function normalize_headers(headers) {
  return $low_request.normalize_headers(headers);
}

/**
 * Construct a collected HTTP response.
 */
export function response(status, headers, body, trailers) {
  return $http_response.new$(status, headers, body, trailers);
}

/**
 * Decode a response body as UTF-8 text.
 */
export function body_text(response) {
  return $http_response.body_text(response);
}

/**
 * Send one request and collect the full response.
 */
export function request(method, path) {
  return $http_client.new$(method, path);
}

/**
 * Construct default high-level WebSocket connection options.
 */
export function websocket_options() {
  return $websocket.options();
}
