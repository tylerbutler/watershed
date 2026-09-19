import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $types from "../spillway/types.d.mts";

export class ThrottlingError extends _.CustomType {}
export function NackErrorType$ThrottlingError(): NackErrorType$;
export function NackErrorType$isThrottlingError(
  value: any,
): value is NackErrorType$;

export class InvalidScopeError extends _.CustomType {}
export function NackErrorType$InvalidScopeError(): NackErrorType$;
export function NackErrorType$isInvalidScopeError(
  value: any,
): value is NackErrorType$;

export class BadRequestError extends _.CustomType {}
export function NackErrorType$BadRequestError(): NackErrorType$;
export function NackErrorType$isBadRequestError(
  value: any,
): value is NackErrorType$;

export class LimitExceededError extends _.CustomType {}
export function NackErrorType$LimitExceededError(): NackErrorType$;
export function NackErrorType$isLimitExceededError(
  value: any,
): value is NackErrorType$;

export type NackErrorType$ = ThrottlingError | InvalidScopeError | BadRequestError | LimitExceededError;

export class NackContent extends _.CustomType {
  /** @deprecated */
  constructor(
    code: number,
    error_type: NackErrorType$,
    message: string,
    retry_after: $option.Option$<number>
  );
  /** @deprecated */
  code: number;
  /** @deprecated */
  error_type: NackErrorType$;
  /** @deprecated */
  message: string;
  /** @deprecated */
  retry_after: $option.Option$<number>;
}
export function NackContent$NackContent(
  code: number,
  error_type: NackErrorType$,
  message: string,
  retry_after: $option.Option$<number>,
): NackContent$;
export function NackContent$isNackContent(value: any): value is NackContent$;
export function NackContent$NackContent$0(value: NackContent$): number;
export function NackContent$NackContent$code(value: NackContent$): number;
export function NackContent$NackContent$1(value: NackContent$): NackErrorType$;
export function NackContent$NackContent$error_type(value: NackContent$): NackErrorType$;
export function NackContent$NackContent$2(
  value: NackContent$,
): string;
export function NackContent$NackContent$message(value: NackContent$): string;
export function NackContent$NackContent$3(value: NackContent$): $option.Option$<
  number
>;
export function NackContent$NackContent$retry_after(value: NackContent$): $option.Option$<
  number
>;

export type NackContent$ = NackContent;

export class Nack extends _.CustomType {
  /** @deprecated */
  constructor(
    operation: $option.Option$<$types.DocumentMessage$>,
    sequence_number: number,
    content: NackContent$
  );
  /** @deprecated */
  operation: $option.Option$<$types.DocumentMessage$>;
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  content: NackContent$;
}
export function Nack$Nack(
  operation: $option.Option$<$types.DocumentMessage$>,
  sequence_number: number,
  content: NackContent$,
): Nack$;
export function Nack$isNack(value: any): value is Nack$;
export function Nack$Nack$0(value: Nack$): $option.Option$<
  $types.DocumentMessage$
>;
export function Nack$Nack$operation(value: Nack$): $option.Option$<
  $types.DocumentMessage$
>;
export function Nack$Nack$1(value: Nack$): number;
export function Nack$Nack$sequence_number(value: Nack$): number;
export function Nack$Nack$2(value: Nack$): NackContent$;
export function Nack$Nack$content(value: Nack$): NackContent$;

export type Nack$ = Nack;

export function nack_error_type_to_string(t: NackErrorType$): string;

export function nack_error_type_from_string(s: string): _.Result<
  NackErrorType$,
  undefined
>;

export function bad_request(
  message: string,
  op: $option.Option$<$types.DocumentMessage$>
): Nack$;

export function invalid_scope(
  required_scope: string,
  op: $option.Option$<$types.DocumentMessage$>
): Nack$;

export function throttled(
  retry_after_seconds: number,
  op: $option.Option$<$types.DocumentMessage$>
): Nack$;

export function limit_exceeded(
  message: string,
  op: $option.Option$<$types.DocumentMessage$>
): Nack$;

export function read_only_client(op: $option.Option$<$types.DocumentMessage$>): Nack$;

export function invalid_csn(
  expected: number,
  received: number,
  op: $option.Option$<$types.DocumentMessage$>
): Nack$;

export function message_too_large(
  max_size: number,
  actual_size: number,
  op: $option.Option$<$types.DocumentMessage$>
): Nack$;

export function invalid_rsn(
  current_sn: number,
  received_rsn: number,
  op: $option.Option$<$types.DocumentMessage$>
): Nack$;

export function unknown_client(client_id: string): Nack$;
