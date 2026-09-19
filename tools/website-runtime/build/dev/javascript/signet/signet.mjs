/// <reference types="./signet.d.mts" />
import * as $jwt from "./signet/jwt.mjs";
import * as $types from "./signet/types.mjs";

/**
 * Verify an HS256 signature and parse the payload into `TokenClaims`. Does not
 * validate tenant/document/expiry — pair with the `signet/jwt` validators.
 */
export function verify_signature(token, secret) {
  return $jwt.verify_signature(token, secret);
}

/**
 * Extract a bare JWT from an `Authorization` header value (Basic / Bearer).
 */
export function extract_token(authorization) {
  return $jwt.extract_token(authorization);
}

/**
 * Mint a strict HS256 document token (version "1.0").
 */
export function mint_token(
  tenant,
  document_id,
  scopes,
  user_id,
  secret,
  now,
  expires_in
) {
  return $jwt.mint_token(
    tenant,
    document_id,
    scopes,
    user_id,
    secret,
    now,
    expires_in,
  );
}
