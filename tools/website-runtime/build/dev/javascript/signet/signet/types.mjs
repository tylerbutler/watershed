/// <reference types="./types.d.mts" />
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $dynamic from "../../gleam_stdlib/gleam/dynamic.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";

export class User extends $CustomType {
  constructor(id, properties) {
    super();
    this.id = id;
    this.properties = properties;
  }
}
export const User$User = (id, properties) => new User(id, properties);
export const User$isUser = (value) => value instanceof User;
export const User$User$id = (value) => value.id;
export const User$User$0 = (value) => value.id;
export const User$User$properties = (value) => value.properties;
export const User$User$1 = (value) => value.properties;

export class DocRead extends $CustomType {}
export const Scope$DocRead$const = new DocRead();
export const Scope$DocRead = () => Scope$DocRead$const;
export const Scope$isDocRead = (value) => value instanceof DocRead;

export class DocWrite extends $CustomType {}
export const Scope$DocWrite$const = new DocWrite();
export const Scope$DocWrite = () => Scope$DocWrite$const;
export const Scope$isDocWrite = (value) => value instanceof DocWrite;

export class SummaryRead extends $CustomType {}
export const Scope$SummaryRead$const = new SummaryRead();
export const Scope$SummaryRead = () => Scope$SummaryRead$const;
export const Scope$isSummaryRead = (value) => value instanceof SummaryRead;

export class SummaryWrite extends $CustomType {}
export const Scope$SummaryWrite$const = new SummaryWrite();
export const Scope$SummaryWrite = () => Scope$SummaryWrite$const;
export const Scope$isSummaryWrite = (value) => value instanceof SummaryWrite;

export class TokenClaims extends $CustomType {
  constructor(document_id, scopes, tenant_id, user, issued_at, expiration, version, jti) {
    super();
    this.document_id = document_id;
    this.scopes = scopes;
    this.tenant_id = tenant_id;
    this.user = user;
    this.issued_at = issued_at;
    this.expiration = expiration;
    this.version = version;
    this.jti = jti;
  }
}
export const TokenClaims$TokenClaims = (document_id, scopes, tenant_id, user, issued_at, expiration, version, jti) =>
  new TokenClaims(document_id,
  scopes,
  tenant_id,
  user,
  issued_at,
  expiration,
  version,
  jti);
export const TokenClaims$isTokenClaims = (value) =>
  value instanceof TokenClaims;
export const TokenClaims$TokenClaims$document_id = (value) => value.document_id;
export const TokenClaims$TokenClaims$0 = (value) => value.document_id;
export const TokenClaims$TokenClaims$scopes = (value) => value.scopes;
export const TokenClaims$TokenClaims$1 = (value) => value.scopes;
export const TokenClaims$TokenClaims$tenant_id = (value) => value.tenant_id;
export const TokenClaims$TokenClaims$2 = (value) => value.tenant_id;
export const TokenClaims$TokenClaims$user = (value) => value.user;
export const TokenClaims$TokenClaims$3 = (value) => value.user;
export const TokenClaims$TokenClaims$issued_at = (value) => value.issued_at;
export const TokenClaims$TokenClaims$4 = (value) => value.issued_at;
export const TokenClaims$TokenClaims$expiration = (value) => value.expiration;
export const TokenClaims$TokenClaims$5 = (value) => value.expiration;
export const TokenClaims$TokenClaims$version = (value) => value.version;
export const TokenClaims$TokenClaims$6 = (value) => value.version;
export const TokenClaims$TokenClaims$jti = (value) => value.jti;
export const TokenClaims$TokenClaims$7 = (value) => value.jti;

/**
 * Encode a scope to its Fluid wire string.
 */
export function scope_to_string(scope) {
  if (scope instanceof DocRead) {
    return "doc:read";
  } else if (scope instanceof DocWrite) {
    return "doc:write";
  } else if (scope instanceof SummaryRead) {
    return "summary:read";
  } else {
    return "summary:write";
  }
}

/**
 * Decode a Fluid wire scope string.
 */
export function scope_from_string(value) {
  if (value === "doc:read") {
    return new Ok(Scope$DocRead$const);
  } else if (value === "doc:write") {
    return new Ok(Scope$DocWrite$const);
  } else if (value === "summary:read") {
    return new Ok(Scope$SummaryRead$const);
  } else if (value === "summary:write") {
    return new Ok(Scope$SummaryWrite$const);
  } else {
    return new Error(undefined);
  }
}

/**
 * Encode typed scopes to their wire strings (for constructing claims).
 */
export function scopes_to_strings(scopes) {
  return $list.map(scopes, scope_to_string);
}

/**
 * Decode wire scope strings to typed scopes, dropping any unrecognized ones.
 */
export function scopes_from_strings(scopes) {
  return $list.filter_map(scopes, scope_from_string);
}
