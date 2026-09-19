import type * as $types from "../../signet/signet/types.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $types from "../spillway/types.d.mts";

export class MessageTooLarge extends _.CustomType {
  /** @deprecated */
  constructor(max: number, actual: number);
  /** @deprecated */
  max: number;
  /** @deprecated */
  actual: number;
}
export function ValidationError$MessageTooLarge(
  max: number,
  actual: number,
): ValidationError$;
export function ValidationError$isMessageTooLarge(
  value: any,
): value is ValidationError$;
export function ValidationError$MessageTooLarge$0(value: ValidationError$): number;
export function ValidationError$MessageTooLarge$max(
  value: ValidationError$,
): number;
export function ValidationError$MessageTooLarge$1(value: ValidationError$): number;
export function ValidationError$MessageTooLarge$actual(
  value: ValidationError$,
): number;

export class MissingField extends _.CustomType {
  /** @deprecated */
  constructor(name: string);
  /** @deprecated */
  name: string;
}
export function ValidationError$MissingField(name: string): ValidationError$;
export function ValidationError$isMissingField(
  value: any,
): value is ValidationError$;
export function ValidationError$MissingField$0(value: ValidationError$): string;
export function ValidationError$MissingField$name(value: ValidationError$): string;

export class InvalidField extends _.CustomType {
  /** @deprecated */
  constructor(name: string, reason: string);
  /** @deprecated */
  name: string;
  /** @deprecated */
  reason: string;
}
export function ValidationError$InvalidField(
  name: string,
  reason: string,
): ValidationError$;
export function ValidationError$isInvalidField(
  value: any,
): value is ValidationError$;
export function ValidationError$InvalidField$0(value: ValidationError$): string;
export function ValidationError$InvalidField$name(value: ValidationError$): string;
export function ValidationError$InvalidField$1(
  value: ValidationError$,
): string;
export function ValidationError$InvalidField$reason(value: ValidationError$): string;

export class InvalidClientSequenceNumber extends _.CustomType {
  /** @deprecated */
  constructor(expected_gt: number, received: number);
  /** @deprecated */
  expected_gt: number;
  /** @deprecated */
  received: number;
}
export function ValidationError$InvalidClientSequenceNumber(
  expected_gt: number,
  received: number,
): ValidationError$;
export function ValidationError$isInvalidClientSequenceNumber(
  value: any,
): value is ValidationError$;
export function ValidationError$InvalidClientSequenceNumber$0(value: ValidationError$): number;
export function ValidationError$InvalidClientSequenceNumber$expected_gt(
  value: ValidationError$,
): number;
export function ValidationError$InvalidClientSequenceNumber$1(value: ValidationError$): number;
export function ValidationError$InvalidClientSequenceNumber$received(
  value: ValidationError$,
): number;

export class InvalidReferenceSequenceNumber extends _.CustomType {
  /** @deprecated */
  constructor(current_sn: number, received: number);
  /** @deprecated */
  current_sn: number;
  /** @deprecated */
  received: number;
}
export function ValidationError$InvalidReferenceSequenceNumber(
  current_sn: number,
  received: number,
): ValidationError$;
export function ValidationError$isInvalidReferenceSequenceNumber(
  value: any,
): value is ValidationError$;
export function ValidationError$InvalidReferenceSequenceNumber$0(value: ValidationError$): number;
export function ValidationError$InvalidReferenceSequenceNumber$current_sn(
  value: ValidationError$,
): number;
export function ValidationError$InvalidReferenceSequenceNumber$1(value: ValidationError$): number;
export function ValidationError$InvalidReferenceSequenceNumber$received(
  value: ValidationError$,
): number;

export class TokenExpired extends _.CustomType {
  /** @deprecated */
  constructor(expired_at: number, current_time: number);
  /** @deprecated */
  expired_at: number;
  /** @deprecated */
  current_time: number;
}
export function ValidationError$TokenExpired(
  expired_at: number,
  current_time: number,
): ValidationError$;
export function ValidationError$isTokenExpired(
  value: any,
): value is ValidationError$;
export function ValidationError$TokenExpired$0(value: ValidationError$): number;
export function ValidationError$TokenExpired$expired_at(value: ValidationError$): number;
export function ValidationError$TokenExpired$1(
  value: ValidationError$,
): number;
export function ValidationError$TokenExpired$current_time(value: ValidationError$): number;

export class MissingScope extends _.CustomType {
  /** @deprecated */
  constructor(required: string, available: _.List<string>);
  /** @deprecated */
  required: string;
  /** @deprecated */
  available: _.List<string>;
}
export function ValidationError$MissingScope(
  required: string,
  available: _.List<string>,
): ValidationError$;
export function ValidationError$isMissingScope(
  value: any,
): value is ValidationError$;
export function ValidationError$MissingScope$0(value: ValidationError$): string;
export function ValidationError$MissingScope$required(value: ValidationError$): string;
export function ValidationError$MissingScope$1(
  value: ValidationError$,
): _.List<string>;
export function ValidationError$MissingScope$available(value: ValidationError$): _.List<
  string
>;

export class OperationNotAllowed extends _.CustomType {
  /** @deprecated */
  constructor(mode: $types.ConnectionMode$, operation: string);
  /** @deprecated */
  mode: $types.ConnectionMode$;
  /** @deprecated */
  operation: string;
}
export function ValidationError$OperationNotAllowed(
  mode: $types.ConnectionMode$,
  operation: string,
): ValidationError$;
export function ValidationError$isOperationNotAllowed(
  value: any,
): value is ValidationError$;
export function ValidationError$OperationNotAllowed$0(value: ValidationError$): $types.ConnectionMode$;
export function ValidationError$OperationNotAllowed$mode(
  value: ValidationError$,
): $types.ConnectionMode$;
export function ValidationError$OperationNotAllowed$1(value: ValidationError$): string;
export function ValidationError$OperationNotAllowed$operation(
  value: ValidationError$,
): string;

export type ValidationError$ = MessageTooLarge | MissingField | InvalidField | InvalidClientSequenceNumber | InvalidReferenceSequenceNumber | TokenExpired | MissingScope | OperationNotAllowed;

export type ValidationResult = _.Result<any, ValidationError$>;

export function validate_message_size(message_bytes: number, max_size: number): _.Result<
  undefined,
  ValidationError$
>;

export function validate_write_mode(mode: $types.ConnectionMode$): _.Result<
  undefined,
  ValidationError$
>;

export function validate_scope(
  claims: $types.TokenClaims$,
  required_scope: string
): _.Result<undefined, ValidationError$>;

export function validate_token_expiration(
  claims: $types.TokenClaims$,
  current_time_seconds: number
): _.Result<undefined, ValidationError$>;

export function validate_token_claims(
  claims: $types.TokenClaims$,
  tenant_id: string,
  document_id: string
): _.Result<undefined, ValidationError$>;

export function validate_csn(received_csn: number, last_csn: number): _.Result<
  undefined,
  ValidationError$
>;

export function validate_rsn(received_rsn: number, current_sn: number): _.Result<
  undefined,
  ValidationError$
>;

export function validate_document_message(
  msg: $types.DocumentMessage$,
  client_mode: $types.ConnectionMode$,
  last_csn: number,
  current_sn: number,
  max_message_size: number,
  message_bytes: number
): _.Result<undefined, ValidationError$>;

export function format_error(error: ValidationError$): string;
