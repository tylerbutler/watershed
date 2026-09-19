/// <reference types="./jwt.d.mts" />
import * as $crypto from "../../gleam_crypto/gleam/crypto.mjs";
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $bit_array from "../../gleam_stdlib/gleam/bit_array.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import { Ok, Error, toList, Empty as $Empty, CustomType as $CustomType } from "../gleam.mjs";
import * as $types from "../signet/types.mjs";
import {
  TokenClaims,
  User,
  scope_to_string,
  scopes_from_strings,
  scopes_to_strings,
  Scope$SummaryWrite$const,
  Scope$DocRead$const,
  Scope$DocWrite$const,
} from "../signet/types.mjs";

/**
 * Token has expired
 */
export class TokenExpired extends $CustomType {
  constructor(expired_at, current_time) {
    super();
    this.expired_at = expired_at;
    this.current_time = current_time;
  }
}
export const JwtValidationError$TokenExpired = (expired_at, current_time) =>
  new TokenExpired(expired_at, current_time);
export const JwtValidationError$isTokenExpired = (value) =>
  value instanceof TokenExpired;
export const JwtValidationError$TokenExpired$expired_at = (value) =>
  value.expired_at;
export const JwtValidationError$TokenExpired$0 = (value) => value.expired_at;
export const JwtValidationError$TokenExpired$current_time = (value) =>
  value.current_time;
export const JwtValidationError$TokenExpired$1 = (value) => value.current_time;

/**
 * Token tenant doesn't match request
 */
export class TenantMismatch extends $CustomType {
  constructor(token_tenant, request_tenant) {
    super();
    this.token_tenant = token_tenant;
    this.request_tenant = request_tenant;
  }
}
export const JwtValidationError$TenantMismatch = (token_tenant, request_tenant) =>
  new TenantMismatch(token_tenant, request_tenant);
export const JwtValidationError$isTenantMismatch = (value) =>
  value instanceof TenantMismatch;
export const JwtValidationError$TenantMismatch$token_tenant = (value) =>
  value.token_tenant;
export const JwtValidationError$TenantMismatch$0 = (value) =>
  value.token_tenant;
export const JwtValidationError$TenantMismatch$request_tenant = (value) =>
  value.request_tenant;
export const JwtValidationError$TenantMismatch$1 = (value) =>
  value.request_tenant;

/**
 * Token document doesn't match request
 */
export class DocumentMismatch extends $CustomType {
  constructor(token_document, request_document) {
    super();
    this.token_document = token_document;
    this.request_document = request_document;
  }
}
export const JwtValidationError$DocumentMismatch = (token_document, request_document) =>
  new DocumentMismatch(token_document, request_document);
export const JwtValidationError$isDocumentMismatch = (value) =>
  value instanceof DocumentMismatch;
export const JwtValidationError$DocumentMismatch$token_document = (value) =>
  value.token_document;
export const JwtValidationError$DocumentMismatch$0 = (value) =>
  value.token_document;
export const JwtValidationError$DocumentMismatch$request_document = (value) =>
  value.request_document;
export const JwtValidationError$DocumentMismatch$1 = (value) =>
  value.request_document;

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
export const JwtValidationError$MissingScope = (required, available) =>
  new MissingScope(required, available);
export const JwtValidationError$isMissingScope = (value) =>
  value instanceof MissingScope;
export const JwtValidationError$MissingScope$required = (value) =>
  value.required;
export const JwtValidationError$MissingScope$0 = (value) => value.required;
export const JwtValidationError$MissingScope$available = (value) =>
  value.available;
export const JwtValidationError$MissingScope$1 = (value) => value.available;

/**
 * Token is missing a required claim
 */
export class MissingClaim extends $CustomType {
  constructor(claim_name) {
    super();
    this.claim_name = claim_name;
  }
}
export const JwtValidationError$MissingClaim = (claim_name) =>
  new MissingClaim(claim_name);
export const JwtValidationError$isMissingClaim = (value) =>
  value instanceof MissingClaim;
export const JwtValidationError$MissingClaim$claim_name = (value) =>
  value.claim_name;
export const JwtValidationError$MissingClaim$0 = (value) => value.claim_name;

/**
 * Token claim has invalid value
 */
export class InvalidClaim extends $CustomType {
  constructor(claim_name, reason) {
    super();
    this.claim_name = claim_name;
    this.reason = reason;
  }
}
export const JwtValidationError$InvalidClaim = (claim_name, reason) =>
  new InvalidClaim(claim_name, reason);
export const JwtValidationError$isInvalidClaim = (value) =>
  value instanceof InvalidClaim;
export const JwtValidationError$InvalidClaim$claim_name = (value) =>
  value.claim_name;
export const JwtValidationError$InvalidClaim$0 = (value) => value.claim_name;
export const JwtValidationError$InvalidClaim$reason = (value) => value.reason;
export const JwtValidationError$InvalidClaim$1 = (value) => value.reason;

/**
 * Malformed token, header, or `Authorization` value.
 */
export class BadFormat extends $CustomType {}
export const JwtCryptoError$BadFormat$const = new BadFormat();
export const JwtCryptoError$BadFormat = () => JwtCryptoError$BadFormat$const;
export const JwtCryptoError$isBadFormat = (value) => value instanceof BadFormat;

/**
 * Signature did not match (or an empty secret was supplied).
 */
export class BadSignature extends $CustomType {}
export const JwtCryptoError$BadSignature$const = new BadSignature();
export const JwtCryptoError$BadSignature = () =>
  JwtCryptoError$BadSignature$const;
export const JwtCryptoError$isBadSignature = (value) =>
  value instanceof BadSignature;

/**
 * Validate that the token has not expired
 */
export function validate_expiration(claims, current_time_seconds) {
  let $ = claims.expiration > current_time_seconds;
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(new TokenExpired(claims.expiration, current_time_seconds));
  }
}

/**
 * Validate that the token tenant matches the request tenant
 */
export function validate_tenant(claims, request_tenant_id) {
  let $ = claims.tenant_id === request_tenant_id;
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(new TenantMismatch(claims.tenant_id, request_tenant_id));
  }
}

/**
 * Validate that the token document matches the request document
 */
export function validate_document(claims, request_document_id) {
  let $ = claims.document_id === request_document_id;
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(
      new DocumentMismatch(claims.document_id, request_document_id),
    );
  }
}

/**
 * Validate that the token has the required scope
 */
export function validate_scope(claims, required_scope) {
  let $ = $list.contains(claims.scopes, required_scope);
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(new MissingScope(required_scope, claims.scopes));
  }
}

/**
 * Check if token has a specific scope (returns Bool, doesn't error)
 */
export function has_scope(claims, scope) {
  return $list.contains(claims.scopes, scope);
}

/**
 * Check if token has read permission
 */
export function has_read_scope(claims) {
  return has_scope(claims, Scope$DocRead$const);
}

/**
 * Check if token has write permission
 */
export function has_write_scope(claims) {
  return has_scope(claims, Scope$DocWrite$const);
}

/**
 * Check if token has summary write permission
 */
export function has_summary_write_scope(claims) {
  return has_scope(claims, Scope$SummaryWrite$const);
}

/**
 * Validate all claims for a document connection
 * Per spec section 3.3:
 * 1. Expiration check
 * 2. Tenant match
 * 3. Document match
 */
export function validate_connection_claims(
  claims,
  tenant_id,
  document_id,
  current_time_seconds
) {
  return $result.try$(
    validate_expiration(claims, current_time_seconds),
    (_) => {
      return $result.try$(
        validate_tenant(claims, tenant_id),
        (_) => {
          return $result.try$(
            validate_document(claims, document_id),
            (_) => { return new Ok(undefined); },
          );
        },
      );
    },
  );
}

/**
 * Validate claims for read access
 * Requires doc:read scope in addition to connection validation
 */
export function validate_read_access(
  claims,
  tenant_id,
  document_id,
  current_time_seconds
) {
  return $result.try$(
    validate_connection_claims(
      claims,
      tenant_id,
      document_id,
      current_time_seconds,
    ),
    (_) => {
      return $result.try$(
        validate_scope(claims, Scope$DocRead$const),
        (_) => { return new Ok(undefined); },
      );
    },
  );
}

/**
 * Validate claims for write access
 * Requires doc:write scope in addition to read access validation
 */
export function validate_write_access(
  claims,
  tenant_id,
  document_id,
  current_time_seconds
) {
  return $result.try$(
    validate_read_access(claims, tenant_id, document_id, current_time_seconds),
    (_) => {
      return $result.try$(
        validate_scope(claims, Scope$DocWrite$const),
        (_) => { return new Ok(undefined); },
      );
    },
  );
}

/**
 * Validate claims for summary write access
 * Requires summary:write scope in addition to read access
 */
export function validate_summary_access(
  claims,
  tenant_id,
  document_id,
  current_time_seconds
) {
  return $result.try$(
    validate_read_access(claims, tenant_id, document_id, current_time_seconds),
    (_) => {
      return $result.try$(
        validate_scope(claims, Scope$SummaryWrite$const),
        (_) => { return new Ok(undefined); },
      );
    },
  );
}

/**
 * Format JWT validation error as human-readable message
 */
export function format_error(error) {
  if (error instanceof TokenExpired) {
    let expired_at = error.expired_at;
    let current_time = error.current_time;
    return ((("Token expired at " + $int.to_string(expired_at)) + " (current time: ") + $int.to_string(
      current_time,
    )) + ")";
  } else if (error instanceof TenantMismatch) {
    let token_tenant = error.token_tenant;
    let request_tenant = error.request_tenant;
    return ((("Token tenant '" + token_tenant) + "' does not match request tenant '") + request_tenant) + "'";
  } else if (error instanceof DocumentMismatch) {
    let token_document = error.token_document;
    let request_document = error.request_document;
    return ((("Token document '" + token_document) + "' does not match request document '") + request_document) + "'";
  } else if (error instanceof MissingScope) {
    let required = error.required;
    return "Missing required scope: " + scope_to_string(required);
  } else if (error instanceof MissingClaim) {
    let claim_name = error.claim_name;
    return "Missing required claim: " + claim_name;
  } else {
    let claim_name = error.claim_name;
    let reason = error.reason;
    return (("Invalid claim '" + claim_name) + "': ") + reason;
  }
}

/**
 * Get HTTP status code for JWT validation error
 */
export function error_to_http_code(error) {
  if (error instanceof TokenExpired) {
    return 401;
  } else if (error instanceof TenantMismatch) {
    return 403;
  } else if (error instanceof DocumentMismatch) {
    return 403;
  } else if (error instanceof MissingScope) {
    return 403;
  } else if (error instanceof MissingClaim) {
    return 401;
  } else {
    return 401;
  }
}

function extract_basic_token(token) {
  let $ = $string.contains(token, ".");
  if ($) {
    return new Ok(token);
  } else {
    return $result.try$(
      (() => {
        let _pipe = $bit_array.base64_decode(token);
        return $result.replace_error(_pipe, JwtCryptoError$BadFormat$const);
      })(),
      (credentials) => {
        return $result.try$(
          (() => {
            let _pipe = $bit_array.to_string(credentials);
            return $result.replace_error(_pipe, JwtCryptoError$BadFormat$const);
          })(),
          (credentials) => {
            let $1 = $string.split(credentials, ":");
            if ($1 instanceof $Empty) {
              return new Error(JwtCryptoError$BadFormat$const);
            } else {
              let $2 = $1.tail;
              if ($2 instanceof $Empty) {
                return new Error(JwtCryptoError$BadFormat$const);
              } else {
                let $3 = $2.tail;
                if ($3 instanceof $Empty) {
                  let token$1 = $2.head;
                  if (token$1 !== "") {
                    return new Ok(token$1);
                  } else {
                    return new Error(JwtCryptoError$BadFormat$const);
                  }
                } else {
                  return new Error(JwtCryptoError$BadFormat$const);
                }
              }
            }
          },
        );
      },
    );
  }
}

/**
 * Extract a bare JWT from an `Authorization` header value. Accepts
 * Routerlicious's `Basic <base64(user:jwt)>` scheme and the conventional
 * `Bearer <jwt>` scheme (and a `Basic <jwt>` shorthand when the value is
 * already a dotted JWT).
 */
export function extract_token(authorization) {
  let $ = $string.split(authorization, " ");
  if ($ instanceof $Empty) {
    return new Error(JwtCryptoError$BadFormat$const);
  } else {
    let $1 = $.tail;
    if ($1 instanceof $Empty) {
      return new Error(JwtCryptoError$BadFormat$const);
    } else {
      let $2 = $1.tail;
      if ($2 instanceof $Empty) {
        let $3 = $.head;
        if ($3 === "Basic") {
          let token = $1.head;
          if (token !== "") {
            return extract_basic_token(token);
          } else {
            return new Error(JwtCryptoError$BadFormat$const);
          }
        } else if ($3 === "Bearer") {
          let token = $1.head;
          if (token !== "") {
            return new Ok(token);
          } else {
            return new Error(JwtCryptoError$BadFormat$const);
          }
        } else {
          return new Error(JwtCryptoError$BadFormat$const);
        }
      } else {
        return new Error(JwtCryptoError$BadFormat$const);
      }
    }
  }
}

function parse_claims(payload) {
  let dec = $decode.field(
    "documentId",
    $decode.string,
    (doc) => {
      return $decode.field(
        "tenantId",
        $decode.string,
        (tenant) => {
          return $decode.field(
            "exp",
            $decode.int,
            (exp) => {
              return $decode.field(
                "scopes",
                $decode.list($decode.string),
                (scope_strings) => {
                  let scopes = scopes_from_strings(scope_strings);
                  return $decode.field(
                    "user",
                    $decode.field(
                      "id",
                      $decode.string,
                      (id) => {
                        return $decode.optional_field(
                          "name",
                          id,
                          $decode.string,
                          (name) => {
                            return $decode.success(
                              new User(
                                id,
                                $dict.from_list(
                                  toList([["name", $dynamic.string(name)]]),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    (user) => {
                      return $decode.field(
                        "iat",
                        $decode.int,
                        (issued_at) => {
                          return $decode.field(
                            "ver",
                            $decode.string,
                            (version) => {
                              return $decode.optional_field(
                                "jti",
                                Option$None$const,
                                $decode.optional($decode.string),
                                (jti) => {
                                  return $decode.success(
                                    new TokenClaims(
                                      doc,
                                      scopes,
                                      tenant,
                                      user,
                                      issued_at,
                                      exp,
                                      version,
                                      jti,
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
  return $result.try$(
    (() => {
      let _pipe = $bit_array.base64_url_decode(payload);
      return $result.replace_error(_pipe, JwtCryptoError$BadFormat$const);
    })(),
    (bytes) => {
      return $result.try$(
        (() => {
          let _pipe = $bit_array.to_string(bytes);
          return $result.replace_error(_pipe, JwtCryptoError$BadFormat$const);
        })(),
        (text) => {
          return $result.try$(
            (() => {
              let _pipe = $json.parse(text, dec);
              return $result.replace_error(
                _pipe,
                JwtCryptoError$BadFormat$const,
              );
            })(),
            (claims) => {
              let $ = claims.version === "1.0";
              let $1 = claims.user.id !== "";
              if ($ && $1) {
                return new Ok(claims);
              } else {
                return new Error(JwtCryptoError$BadFormat$const);
              }
            },
          );
        },
      );
    },
  );
}

function verify_header(header) {
  return $result.try$(
    (() => {
      let _pipe = $bit_array.base64_url_decode(header);
      return $result.replace_error(_pipe, JwtCryptoError$BadFormat$const);
    })(),
    (bytes) => {
      return $result.try$(
        (() => {
          let _pipe = $bit_array.to_string(bytes);
          return $result.replace_error(_pipe, JwtCryptoError$BadFormat$const);
        })(),
        (text) => {
          return $result.try$(
            (() => {
              let _pipe = $json.parse(
                text,
                $decode.field("alg", $decode.string, $decode.success),
              );
              return $result.replace_error(
                _pipe,
                JwtCryptoError$BadFormat$const,
              );
            })(),
            (algorithm) => {
              if (algorithm === "HS256") {
                return new Ok(undefined);
              } else {
                return new Error(JwtCryptoError$BadFormat$const);
              }
            },
          );
        },
      );
    },
  );
}

/**
 * Verify an HS256 signature and parse the payload into `TokenClaims`. Does not
 * validate tenant/document/expiry — pair with the `validate_*` functions.
 */
export function verify_signature(token, secret) {
  let $ = $string.split(token, ".");
  if (secret === "") {
    return new Error(JwtCryptoError$BadSignature$const);
  } else if ($ instanceof $Empty) {
    return new Error(JwtCryptoError$BadFormat$const);
  } else {
    let $1 = $.tail;
    if ($1 instanceof $Empty) {
      return new Error(JwtCryptoError$BadFormat$const);
    } else {
      let $2 = $1.tail;
      if ($2 instanceof $Empty) {
        return new Error(JwtCryptoError$BadFormat$const);
      } else {
        let $3 = $2.tail;
        if ($3 instanceof $Empty) {
          let header = $.head;
          let payload = $1.head;
          let signature = $2.head;
          return $result.try$(
            verify_header(header),
            (_) => {
              let signed = $bit_array.from_string((header + ".") + payload);
              let expected = $crypto.hmac(
                signed,
                $crypto.HashAlgorithm$Sha256$const,
                $bit_array.from_string(secret),
              );
              let $4 = $bit_array.base64_url_decode(signature);
              if ($4 instanceof Ok) {
                let actual = $4[0];
                let $5 = $crypto.secure_compare(actual, expected);
                if ($5) {
                  return parse_claims(payload);
                } else {
                  return new Error(JwtCryptoError$BadSignature$const);
                }
              } else {
                return new Error(JwtCryptoError$BadSignature$const);
              }
            },
          );
        } else {
          return new Error(JwtCryptoError$BadFormat$const);
        }
      }
    }
  }
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
  let _block;
  let _pipe = $json.object(
    toList([["alg", $json.string("HS256")], ["typ", $json.string("JWT")]]),
  );
  let _pipe$1 = $json.to_string(_pipe);
  let _pipe$2 = $bit_array.from_string(_pipe$1);
  _block = $bit_array.base64_url_encode(_pipe$2, false);
  let header = _block;
  let _block$1;
  let _pipe$3 = $json.object(
    toList([
      ["documentId", $json.string(document_id)],
      ["tenantId", $json.string(tenant)],
      ["scopes", $json.array(scopes_to_strings(scopes), $json.string)],
      ["user", $json.object(toList([["id", $json.string(user_id)]]))],
      ["ver", $json.string("1.0")],
      ["iat", $json.int(now)],
      ["exp", $json.int(now + expires_in)],
      [
        "jti",
        (() => {
          let _pipe$3 = $crypto.strong_random_bytes(16);
          let _pipe$4 = $bit_array.base16_encode(_pipe$3);
          let _pipe$5 = $string.lowercase(_pipe$4);
          return $json.string(_pipe$5);
        })(),
      ],
    ]),
  );
  let _pipe$4 = $json.to_string(_pipe$3);
  let _pipe$5 = $bit_array.from_string(_pipe$4);
  _block$1 = $bit_array.base64_url_encode(_pipe$5, false);
  let payload = _block$1;
  let signed = (header + ".") + payload;
  let _block$2;
  let _pipe$6 = $crypto.hmac(
    $bit_array.from_string(signed),
    $crypto.HashAlgorithm$Sha256$const,
    $bit_array.from_string(secret),
  );
  _block$2 = $bit_array.base64_url_encode(_pipe$6, false);
  let signature = _block$2;
  return (signed + ".") + signature;
}
