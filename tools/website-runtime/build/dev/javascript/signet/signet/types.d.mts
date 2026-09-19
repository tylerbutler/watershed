import type * as $dict from "../../gleam_stdlib/gleam/dict.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class User extends _.CustomType {
  /** @deprecated */
  constructor(id: string, properties: $dict.Dict$<string, $dynamic.Dynamic$>);
  /** @deprecated */
  id: string;
  /** @deprecated */
  properties: $dict.Dict$<string, $dynamic.Dynamic$>;
}
export function User$User(
  id: string,
  properties: $dict.Dict$<string, $dynamic.Dynamic$>,
): User$;
export function User$isUser(value: any): value is User$;
export function User$User$0(value: User$): string;
export function User$User$id(value: User$): string;
export function User$User$1(value: User$): $dict.Dict$<
  string,
  $dynamic.Dynamic$
>;
export function User$User$properties(value: User$): $dict.Dict$<
  string,
  $dynamic.Dynamic$
>;

export type User$ = User;

export class DocRead extends _.CustomType {}
export function Scope$DocRead(): Scope$;
export function Scope$isDocRead(value: any): value is Scope$;

export class DocWrite extends _.CustomType {}
export function Scope$DocWrite(): Scope$;
export function Scope$isDocWrite(value: any): value is Scope$;

export class SummaryRead extends _.CustomType {}
export function Scope$SummaryRead(): Scope$;
export function Scope$isSummaryRead(value: any): value is Scope$;

export class SummaryWrite extends _.CustomType {}
export function Scope$SummaryWrite(): Scope$;
export function Scope$isSummaryWrite(value: any): value is Scope$;

export type Scope$ = DocRead | DocWrite | SummaryRead | SummaryWrite;

export class TokenClaims extends _.CustomType {
  /** @deprecated */
  constructor(
    document_id: string,
    scopes: _.List<Scope$>,
    tenant_id: string,
    user: User$,
    issued_at: number,
    expiration: number,
    version: string,
    jti: $option.Option$<string>
  );
  /** @deprecated */
  document_id: string;
  /** @deprecated */
  scopes: _.List<Scope$>;
  /** @deprecated */
  tenant_id: string;
  /** @deprecated */
  user: User$;
  /** @deprecated */
  issued_at: number;
  /** @deprecated */
  expiration: number;
  /** @deprecated */
  version: string;
  /** @deprecated */
  jti: $option.Option$<string>;
}
export function TokenClaims$TokenClaims(
  document_id: string,
  scopes: _.List<Scope$>,
  tenant_id: string,
  user: User$,
  issued_at: number,
  expiration: number,
  version: string,
  jti: $option.Option$<string>,
): TokenClaims$;
export function TokenClaims$isTokenClaims(value: any): value is TokenClaims$;
export function TokenClaims$TokenClaims$0(value: TokenClaims$): string;
export function TokenClaims$TokenClaims$document_id(value: TokenClaims$): string;
export function TokenClaims$TokenClaims$1(
  value: TokenClaims$,
): _.List<Scope$>;
export function TokenClaims$TokenClaims$scopes(value: TokenClaims$): _.List<
  Scope$
>;
export function TokenClaims$TokenClaims$2(value: TokenClaims$): string;
export function TokenClaims$TokenClaims$tenant_id(value: TokenClaims$): string;
export function TokenClaims$TokenClaims$3(value: TokenClaims$): User$;
export function TokenClaims$TokenClaims$user(value: TokenClaims$): User$;
export function TokenClaims$TokenClaims$4(value: TokenClaims$): number;
export function TokenClaims$TokenClaims$issued_at(value: TokenClaims$): number;
export function TokenClaims$TokenClaims$5(value: TokenClaims$): number;
export function TokenClaims$TokenClaims$expiration(value: TokenClaims$): number;
export function TokenClaims$TokenClaims$6(value: TokenClaims$): string;
export function TokenClaims$TokenClaims$version(value: TokenClaims$): string;
export function TokenClaims$TokenClaims$7(value: TokenClaims$): $option.Option$<
  string
>;
export function TokenClaims$TokenClaims$jti(value: TokenClaims$): $option.Option$<
  string
>;

export type TokenClaims$ = TokenClaims;

export function scope_to_string(scope: Scope$): string;

export function scope_from_string(value: string): _.Result<Scope$, undefined>;

export function scopes_to_strings(scopes: _.List<Scope$>): _.List<string>;

export function scopes_from_strings(scopes: _.List<string>): _.List<Scope$>;
