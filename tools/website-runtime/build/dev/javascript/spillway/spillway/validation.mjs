/// <reference types="./validation.d.mts" />
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";
import * as $types from "../spillway/types.mjs";
import {
  WriteMode,
  scope_from_string,
  scope_to_string,
  ConnectionMode$ReadMode$const,
} from "../spillway/types.mjs";

/**
 * Message is too large
 */
export class MessageTooLarge extends $CustomType {
  constructor(max, actual) {
    super();
    this.max = max;
    this.actual = actual;
  }
}
export const ValidationError$MessageTooLarge = (max, actual) =>
  new MessageTooLarge(max, actual);
export const ValidationError$isMessageTooLarge = (value) =>
  value instanceof MessageTooLarge;
export const ValidationError$MessageTooLarge$max = (value) => value.max;
export const ValidationError$MessageTooLarge$0 = (value) => value.max;
export const ValidationError$MessageTooLarge$actual = (value) => value.actual;
export const ValidationError$MessageTooLarge$1 = (value) => value.actual;

/**
 * Required field is missing
 */
export class MissingField extends $CustomType {
  constructor(name) {
    super();
    this.name = name;
  }
}
export const ValidationError$MissingField = (name) => new MissingField(name);
export const ValidationError$isMissingField = (value) =>
  value instanceof MissingField;
export const ValidationError$MissingField$name = (value) => value.name;
export const ValidationError$MissingField$0 = (value) => value.name;

/**
 * Field has invalid value
 */
export class InvalidField extends $CustomType {
  constructor(name, reason) {
    super();
    this.name = name;
    this.reason = reason;
  }
}
export const ValidationError$InvalidField = (name, reason) =>
  new InvalidField(name, reason);
export const ValidationError$isInvalidField = (value) =>
  value instanceof InvalidField;
export const ValidationError$InvalidField$name = (value) => value.name;
export const ValidationError$InvalidField$0 = (value) => value.name;
export const ValidationError$InvalidField$reason = (value) => value.reason;
export const ValidationError$InvalidField$1 = (value) => value.reason;

/**
 * Client sequence number is invalid
 */
export class InvalidClientSequenceNumber extends $CustomType {
  constructor(expected_gt, received) {
    super();
    this.expected_gt = expected_gt;
    this.received = received;
  }
}
export const ValidationError$InvalidClientSequenceNumber = (expected_gt, received) =>
  new InvalidClientSequenceNumber(expected_gt, received);
export const ValidationError$isInvalidClientSequenceNumber = (value) =>
  value instanceof InvalidClientSequenceNumber;
export const ValidationError$InvalidClientSequenceNumber$expected_gt = (value) =>
  value.expected_gt;
export const ValidationError$InvalidClientSequenceNumber$0 = (value) =>
  value.expected_gt;
export const ValidationError$InvalidClientSequenceNumber$received = (value) =>
  value.received;
export const ValidationError$InvalidClientSequenceNumber$1 = (value) =>
  value.received;

/**
 * Reference sequence number is invalid
 */
export class InvalidReferenceSequenceNumber extends $CustomType {
  constructor(current_sn, received) {
    super();
    this.current_sn = current_sn;
    this.received = received;
  }
}
export const ValidationError$InvalidReferenceSequenceNumber = (current_sn, received) =>
  new InvalidReferenceSequenceNumber(current_sn, received);
export const ValidationError$isInvalidReferenceSequenceNumber = (value) =>
  value instanceof InvalidReferenceSequenceNumber;
export const ValidationError$InvalidReferenceSequenceNumber$current_sn = (value) =>
  value.current_sn;
export const ValidationError$InvalidReferenceSequenceNumber$0 = (value) =>
  value.current_sn;
export const ValidationError$InvalidReferenceSequenceNumber$received = (value) =>
  value.received;
export const ValidationError$InvalidReferenceSequenceNumber$1 = (value) =>
  value.received;

/**
 * Token is expired
 */
export class TokenExpired extends $CustomType {
  constructor(expired_at, current_time) {
    super();
    this.expired_at = expired_at;
    this.current_time = current_time;
  }
}
export const ValidationError$TokenExpired = (expired_at, current_time) =>
  new TokenExpired(expired_at, current_time);
export const ValidationError$isTokenExpired = (value) =>
  value instanceof TokenExpired;
export const ValidationError$TokenExpired$expired_at = (value) =>
  value.expired_at;
export const ValidationError$TokenExpired$0 = (value) => value.expired_at;
export const ValidationError$TokenExpired$current_time = (value) =>
  value.current_time;
export const ValidationError$TokenExpired$1 = (value) => value.current_time;

/**
 * Token missing required scope
 */
export class MissingScope extends $CustomType {
  constructor(required, available) {
    super();
    this.required = required;
    this.available = available;
  }
}
export const ValidationError$MissingScope = (required, available) =>
  new MissingScope(required, available);
export const ValidationError$isMissingScope = (value) =>
  value instanceof MissingScope;
export const ValidationError$MissingScope$required = (value) => value.required;
export const ValidationError$MissingScope$0 = (value) => value.required;
export const ValidationError$MissingScope$available = (value) =>
  value.available;
export const ValidationError$MissingScope$1 = (value) => value.available;

/**
 * Client mode doesn't allow operation
 */
export class OperationNotAllowed extends $CustomType {
  constructor(mode, operation) {
    super();
    this.mode = mode;
    this.operation = operation;
  }
}
export const ValidationError$OperationNotAllowed = (mode, operation) =>
  new OperationNotAllowed(mode, operation);
export const ValidationError$isOperationNotAllowed = (value) =>
  value instanceof OperationNotAllowed;
export const ValidationError$OperationNotAllowed$mode = (value) => value.mode;
export const ValidationError$OperationNotAllowed$0 = (value) => value.mode;
export const ValidationError$OperationNotAllowed$operation = (value) =>
  value.operation;
export const ValidationError$OperationNotAllowed$1 = (value) => value.operation;

/**
 * Validate message size
 */
export function validate_message_size(message_bytes, max_size) {
  let $ = message_bytes <= max_size;
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(new MessageTooLarge(max_size, message_bytes));
  }
}

/**
 * Validate that client has write mode
 */
export function validate_write_mode(mode) {
  if (mode instanceof WriteMode) {
    return new Ok(undefined);
  } else {
    return new Error(
      new OperationNotAllowed(ConnectionMode$ReadMode$const, "submitOp"),
    );
  }
}

/**
 * Validate that token has required scope. Keeps the wire-string API; scopes on
 * the claims are typed (`List(Scope)`), so compare via the typed form.
 */
export function validate_scope(claims, required_scope) {
  let available = $list.map(claims.scopes, scope_to_string);
  let $ = scope_from_string(required_scope);
  if ($ instanceof Ok) {
    let scope = $[0];
    let $1 = $list.contains(claims.scopes, scope);
    if ($1) {
      return new Ok(undefined);
    } else {
      return new Error(new MissingScope(required_scope, available));
    }
  } else {
    return new Error(new MissingScope(required_scope, available));
  }
}

/**
 * Validate token is not expired
 */
export function validate_token_expiration(claims, current_time_seconds) {
  let $ = claims.expiration > current_time_seconds;
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(new TokenExpired(claims.expiration, current_time_seconds));
  }
}

/**
 * Validate token claims match request
 */
export function validate_token_claims(claims, tenant_id, document_id) {
  let $ = claims.tenant_id === tenant_id;
  if ($) {
    let $1 = claims.document_id === document_id;
    if ($1) {
      return new Ok(undefined);
    } else {
      return new Error(
        new InvalidField("documentId", "Token document does not match request"),
      );
    }
  } else {
    return new Error(
      new InvalidField("tenantId", "Token tenant does not match request"),
    );
  }
}

/**
 * Validate client sequence number
 */
export function validate_csn(received_csn, last_csn) {
  let $ = received_csn > last_csn;
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(new InvalidClientSequenceNumber(last_csn, received_csn));
  }
}

/**
 * Validate reference sequence number
 */
export function validate_rsn(received_rsn, current_sn) {
  let $ = received_rsn <= current_sn;
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(
      new InvalidReferenceSequenceNumber(current_sn, received_rsn),
    );
  }
}

/**
 * Validate a complete document message for submission
 */
export function validate_document_message(
  msg,
  client_mode,
  last_csn,
  current_sn,
  max_message_size,
  message_bytes
) {
  return $result.try$(
    validate_write_mode(client_mode),
    (_) => {
      return $result.try$(
        validate_message_size(message_bytes, max_message_size),
        (_) => {
          return $result.try$(
            validate_csn(msg.client_sequence_number, last_csn),
            (_) => {
              return $result.try$(
                validate_rsn(msg.reference_sequence_number, current_sn),
                (_) => { return new Ok(undefined); },
              );
            },
          );
        },
      );
    },
  );
}

/**
 * Format validation error as human-readable message
 */
export function format_error(error) {
  if (error instanceof MessageTooLarge) {
    let max = error.max;
    let actual = error.actual;
    return (("Message size " + $int.to_string(actual)) + " exceeds limit ") + $int.to_string(
      max,
    );
  } else if (error instanceof MissingField) {
    let name = error.name;
    return "Missing required field: " + name;
  } else if (error instanceof InvalidField) {
    let name = error.name;
    let reason = error.reason;
    return (("Invalid field '" + name) + "': ") + reason;
  } else if (error instanceof InvalidClientSequenceNumber) {
    let expected_gt = error.expected_gt;
    let received = error.received;
    return (("Invalid client sequence number: expected > " + $int.to_string(
      expected_gt,
    )) + ", received ") + $int.to_string(received);
  } else if (error instanceof InvalidReferenceSequenceNumber) {
    let current_sn = error.current_sn;
    let received = error.received;
    return (("Invalid reference sequence number: current SN is " + $int.to_string(
      current_sn,
    )) + ", received RSN ") + $int.to_string(received);
  } else if (error instanceof TokenExpired) {
    let expired_at = error.expired_at;
    return "Token expired at " + $int.to_string(expired_at);
  } else if (error instanceof MissingScope) {
    let required = error.required;
    return "Missing required scope: " + required;
  } else {
    let operation = error.operation;
    return ("Operation '" + operation) + "' not allowed in read-only mode";
  }
}
