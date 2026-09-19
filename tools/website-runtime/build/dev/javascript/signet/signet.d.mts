import type * as _ from "./gleam.d.mts";
import type * as $jwt from "./signet/jwt.d.mts";
import type * as $types from "./signet/types.d.mts";

export type TokenClaims = $types.TokenClaims$;

export type User = $types.User$;

export type Scope = $types.Scope$;

export function verify_signature(token: string, secret: string): _.Result<
  $types.TokenClaims$,
  $jwt.JwtCryptoError$
>;

export function extract_token(authorization: string): _.Result<
  string,
  $jwt.JwtCryptoError$
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
