import type * as _ from "../gleam.d.mts";
import type * as $types from "../signet/types.d.mts";

export class TokenExpired extends _.CustomType {
  /** @deprecated */
  constructor(expired_at: number, current_time: number);
  /** @deprecated */
  expired_at: number;
  /** @deprecated */
  current_time: number;
}
export function JwtValidationError$TokenExpired(
  expired_at: number,
  current_time: number,
): JwtValidationError$;
export function JwtValidationError$isTokenExpired(
  value: any,
): value is JwtValidationError$;
export function JwtValidationError$TokenExpired$0(value: JwtValidationError$): number;
export function JwtValidationError$TokenExpired$expired_at(
  value: JwtValidationError$,
): number;
export function JwtValidationError$TokenExpired$1(value: JwtValidationError$): number;
export function JwtValidationError$TokenExpired$current_time(
  value: JwtValidationError$,
): number;

export class TenantMismatch extends _.CustomType {
  /** @deprecated */
  constructor(token_tenant: string, request_tenant: string);
  /** @deprecated */
  token_tenant: string;
  /** @deprecated */
  request_tenant: string;
}
export function JwtValidationError$TenantMismatch(
  token_tenant: string,
  request_tenant: string,
): JwtValidationError$;
export function JwtValidationError$isTenantMismatch(
  value: any,
): value is JwtValidationError$;
export function JwtValidationError$TenantMismatch$0(value: JwtValidationError$): string;
export function JwtValidationError$TenantMismatch$token_tenant(
  value: JwtValidationError$,
): string;
export function JwtValidationError$TenantMismatch$1(value: JwtValidationError$): string;
export function JwtValidationError$TenantMismatch$request_tenant(
  value: JwtValidationError$,
): string;

export class DocumentMismatch extends _.CustomType {
  /** @deprecated */
  constructor(token_document: string, request_document: string);
  /** @deprecated */
  token_document: string;
  /** @deprecated */
  request_document: string;
}
export function JwtValidationError$DocumentMismatch(
  token_document: string,
  request_document: string,
): JwtValidationError$;
export function JwtValidationError$isDocumentMismatch(
  value: any,
): value is JwtValidationError$;
export function JwtValidationError$DocumentMismatch$0(value: JwtValidationError$): string;
export function JwtValidationError$DocumentMismatch$token_document(
  value: JwtValidationError$,
): string;
export function JwtValidationError$DocumentMismatch$1(value: JwtValidationError$): string;
export function JwtValidationError$DocumentMismatch$request_document(
  value: JwtValidationError$,
): string;

export class MissingScope extends _.CustomType {
  /** @deprecated */
  constructor(required: $types.Scope$, available: _.List<$types.Scope$>);
  /** @deprecated */
  required: $types.Scope$;
  /** @deprecated */
  available: _.List<$types.Scope$>;
}
export function JwtValidationError$MissingScope(
  required: $types.Scope$,
  available: _.List<$types.Scope$>,
): JwtValidationError$;
export function JwtValidationError$isMissingScope(
  value: any,
): value is JwtValidationError$;
export function JwtValidationError$MissingScope$0(value: JwtValidationError$): $types.Scope$;
export function JwtValidationError$MissingScope$required(
  value: JwtValidationError$,
): $types.Scope$;
export function JwtValidationError$MissingScope$1(value: JwtValidationError$): _.List<
  $types.Scope$
>;
export function JwtValidationError$MissingScope$available(value: JwtValidationError$): _.List<
  $types.Scope$
>;

export class MissingClaim extends _.CustomType {
  /** @deprecated */
  constructor(claim_name: string);
  /** @deprecated */
  claim_name: string;
}
export function JwtValidationError$MissingClaim(
  claim_name: string,
): JwtValidationError$;
export function JwtValidationError$isMissingClaim(
  value: any,
): value is JwtValidationError$;
export function JwtValidationError$MissingClaim$0(value: JwtValidationError$): string;
export function JwtValidationError$MissingClaim$claim_name(
  value: JwtValidationError$,
): string;

export class InvalidClaim extends _.CustomType {
  /** @deprecated */
  constructor(claim_name: string, reason: string);
  /** @deprecated */
  claim_name: string;
  /** @deprecated */
  reason: string;
}
export function JwtValidationError$InvalidClaim(
  claim_name: string,
  reason: string,
): JwtValidationError$;
export function JwtValidationError$isInvalidClaim(
  value: any,
): value is JwtValidationError$;
export function JwtValidationError$InvalidClaim$0(value: JwtValidationError$): string;
export function JwtValidationError$InvalidClaim$claim_name(
  value: JwtValidationError$,
): string;
export function JwtValidationError$InvalidClaim$1(value: JwtValidationError$): string;
export function JwtValidationError$InvalidClaim$reason(
  value: JwtValidationError$,
): string;

export type JwtValidationError$ = TokenExpired | TenantMismatch | DocumentMismatch | MissingScope | MissingClaim | InvalidClaim;

export class BadFormat extends _.CustomType {}
export function JwtCryptoError$BadFormat(): JwtCryptoError$;
export function JwtCryptoError$isBadFormat(
  value: any,
): value is JwtCryptoError$;

export class BadSignature extends _.CustomType {}
export function JwtCryptoError$BadSignature(): JwtCryptoError$;
export function JwtCryptoError$isBadSignature(
  value: any,
): value is JwtCryptoError$;

export type JwtCryptoError$ = BadFormat | BadSignature;

export type JwtValidationResult = _.Result<any, JwtValidationError$>;

export function validate_expiration(
  claims: $types.TokenClaims$,
  current_time_seconds: number
): _.Result<undefined, JwtValidationError$>;

export function validate_tenant(
  claims: $types.TokenClaims$,
  request_tenant_id: string
): _.Result<undefined, JwtValidationError$>;

export function validate_document(
  claims: $types.TokenClaims$,
  request_document_id: string
): _.Result<undefined, JwtValidationError$>;

export function validate_scope(
  claims: $types.TokenClaims$,
  required_scope: $types.Scope$
): _.Result<undefined, JwtValidationError$>;

export function has_scope(claims: $types.TokenClaims$, scope: $types.Scope$): boolean;

export function has_read_scope(claims: $types.TokenClaims$): boolean;

export function has_write_scope(claims: $types.TokenClaims$): boolean;

export function has_summary_write_scope(claims: $types.TokenClaims$): boolean;

export function validate_connection_claims(
  claims: $types.TokenClaims$,
  tenant_id: string,
  document_id: string,
  current_time_seconds: number
): _.Result<undefined, JwtValidationError$>;

export function validate_read_access(
  claims: $types.TokenClaims$,
  tenant_id: string,
  document_id: string,
  current_time_seconds: number
): _.Result<undefined, JwtValidationError$>;

export function validate_write_access(
  claims: $types.TokenClaims$,
  tenant_id: string,
  document_id: string,
  current_time_seconds: number
): _.Result<undefined, JwtValidationError$>;

export function validate_summary_access(
  claims: $types.TokenClaims$,
  tenant_id: string,
  document_id: string,
  current_time_seconds: number
): _.Result<undefined, JwtValidationError$>;

export function format_error(error: JwtValidationError$): string;

export function error_to_http_code(error: JwtValidationError$): number;

export function extract_token(authorization: string): _.Result<
  string,
  JwtCryptoError$
>;

export function verify_signature(token: string, secret: string): _.Result<
  $types.TokenClaims$,
  JwtCryptoError$
>;

export function mint_token(
  tenant: string,
  document_id: string,
  scopes: _.List<$types.Scope$>,
  user_id: string,
  secret: string,
  now: number,
  expires_in: number
): string;
