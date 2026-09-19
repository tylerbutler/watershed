/// <reference types="./nack.d.mts" />
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";
import * as $types from "../spillway/types.mjs";

/**
 * Rate limit exceeded; retry after retryAfter seconds (429)
 */
export class ThrottlingError extends $CustomType {}
export const NackErrorType$ThrottlingError$const = new ThrottlingError();
export const NackErrorType$ThrottlingError = () =>
  NackErrorType$ThrottlingError$const;
export const NackErrorType$isThrottlingError = (value) =>
  value instanceof ThrottlingError;

/**
 * Token lacks required scope; obtain new token (403)
 */
export class InvalidScopeError extends $CustomType {}
export const NackErrorType$InvalidScopeError$const = new InvalidScopeError();
export const NackErrorType$InvalidScopeError = () =>
  NackErrorType$InvalidScopeError$const;
export const NackErrorType$isInvalidScopeError = (value) =>
  value instanceof InvalidScopeError;

/**
 * Malformed request; fix and retry immediately (400)
 */
export class BadRequestError extends $CustomType {}
export const NackErrorType$BadRequestError$const = new BadRequestError();
export const NackErrorType$BadRequestError = () =>
  NackErrorType$BadRequestError$const;
export const NackErrorType$isBadRequestError = (value) =>
  value instanceof BadRequestError;

/**
 * Server limit exceeded; do not retry (429)
 */
export class LimitExceededError extends $CustomType {}
export const NackErrorType$LimitExceededError$const = new LimitExceededError();
export const NackErrorType$LimitExceededError = () =>
  NackErrorType$LimitExceededError$const;
export const NackErrorType$isLimitExceededError = (value) =>
  value instanceof LimitExceededError;

export class NackContent extends $CustomType {
  constructor(code, error_type, message, retry_after) {
    super();
    this.code = code;
    this.error_type = error_type;
    this.message = message;
    this.retry_after = retry_after;
  }
}
export const NackContent$NackContent = (code, error_type, message, retry_after) =>
  new NackContent(code, error_type, message, retry_after);
export const NackContent$isNackContent = (value) =>
  value instanceof NackContent;
export const NackContent$NackContent$code = (value) => value.code;
export const NackContent$NackContent$0 = (value) => value.code;
export const NackContent$NackContent$error_type = (value) => value.error_type;
export const NackContent$NackContent$1 = (value) => value.error_type;
export const NackContent$NackContent$message = (value) => value.message;
export const NackContent$NackContent$2 = (value) => value.message;
export const NackContent$NackContent$retry_after = (value) => value.retry_after;
export const NackContent$NackContent$3 = (value) => value.retry_after;

export class Nack extends $CustomType {
  constructor(operation, sequence_number, content) {
    super();
    this.operation = operation;
    this.sequence_number = sequence_number;
    this.content = content;
  }
}
export const Nack$Nack = (operation, sequence_number, content) =>
  new Nack(operation, sequence_number, content);
export const Nack$isNack = (value) => value instanceof Nack;
export const Nack$Nack$operation = (value) => value.operation;
export const Nack$Nack$0 = (value) => value.operation;
export const Nack$Nack$sequence_number = (value) => value.sequence_number;
export const Nack$Nack$1 = (value) => value.sequence_number;
export const Nack$Nack$content = (value) => value.content;
export const Nack$Nack$2 = (value) => value.content;

/**
 * Convert nack error type to wire format string
 */
export function nack_error_type_to_string(t) {
  if (t instanceof ThrottlingError) {
    return "ThrottlingError";
  } else if (t instanceof InvalidScopeError) {
    return "InvalidScopeError";
  } else if (t instanceof BadRequestError) {
    return "BadRequestError";
  } else {
    return "LimitExceededError";
  }
}

/**
 * Parse nack error type from wire format string
 */
export function nack_error_type_from_string(s) {
  if (s === "ThrottlingError") {
    return new Ok(NackErrorType$ThrottlingError$const);
  } else if (s === "InvalidScopeError") {
    return new Ok(NackErrorType$InvalidScopeError$const);
  } else if (s === "BadRequestError") {
    return new Ok(NackErrorType$BadRequestError$const);
  } else if (s === "LimitExceededError") {
    return new Ok(NackErrorType$LimitExceededError$const);
  } else {
    return new Error(undefined);
  }
}

/**
 * Create a nack for an invalid message format
 */
export function bad_request(message, op) {
  return new Nack(
    op,
    -1,
    new NackContent(
      400,
      NackErrorType$BadRequestError$const,
      message,
      $option.Option$None$const,
    ),
  );
}

/**
 * Create a nack for missing required scope
 */
export function invalid_scope(required_scope, op) {
  return new Nack(
    op,
    -1,
    new NackContent(
      403,
      NackErrorType$InvalidScopeError$const,
      "Missing required scope: " + required_scope,
      $option.Option$None$const,
    ),
  );
}

/**
 * Create a nack for rate limiting
 */
export function throttled(retry_after_seconds, op) {
  return new Nack(
    op,
    -1,
    new NackContent(
      429,
      NackErrorType$ThrottlingError$const,
      "Rate limit exceeded",
      new $option.Some(retry_after_seconds),
    ),
  );
}

/**
 * Create a nack for server limit exceeded
 */
export function limit_exceeded(message, op) {
  return new Nack(
    op,
    -1,
    new NackContent(
      429,
      NackErrorType$LimitExceededError$const,
      message,
      $option.Option$None$const,
    ),
  );
}

/**
 * Create a nack for read-only client trying to write
 */
export function read_only_client(op) {
  return new Nack(
    op,
    -1,
    new NackContent(
      400,
      NackErrorType$BadRequestError$const,
      "Client is in read-only mode",
      $option.Option$None$const,
    ),
  );
}

/**
 * Create a nack for invalid CSN
 */
export function invalid_csn(expected, received, op) {
  return new Nack(
    op,
    -1,
    new NackContent(
      400,
      NackErrorType$BadRequestError$const,
      (("Invalid client sequence number: expected > " + $int.to_string(expected)) + ", received ") + $int.to_string(
        received,
      ),
      $option.Option$None$const,
    ),
  );
}

/**
 * Create a nack for message too large
 */
export function message_too_large(max_size, actual_size, op) {
  return new Nack(
    op,
    -1,
    new NackContent(
      413,
      NackErrorType$BadRequestError$const,
      (("Message size " + $int.to_string(actual_size)) + " exceeds limit ") + $int.to_string(
        max_size,
      ),
      $option.Option$None$const,
    ),
  );
}

/**
 * Create a nack for an invalid RSN
 */
export function invalid_rsn(current_sn, received_rsn, op) {
  return new Nack(
    op,
    -1,
    new NackContent(
      400,
      NackErrorType$BadRequestError$const,
      (("Invalid RSN: current SN is " + $int.to_string(current_sn)) + ", received ") + $int.to_string(
        received_rsn,
      ),
      $option.Option$None$const,
    ),
  );
}

/**
 * Create a nack for an unknown client
 */
export function unknown_client(client_id) {
  return new Nack(
    $option.Option$None$const,
    -1,
    new NackContent(
      400,
      NackErrorType$BadRequestError$const,
      "Unknown client: " + client_id,
      $option.Option$None$const,
    ),
  );
}
