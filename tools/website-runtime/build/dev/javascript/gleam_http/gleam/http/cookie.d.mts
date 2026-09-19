import type * as $option from "../../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $http from "../../gleam/http.d.mts";

export class Lax extends _.CustomType {}
export function SameSitePolicy$Lax(): SameSitePolicy$;
export function SameSitePolicy$isLax(value: any): value is SameSitePolicy$;

export class Strict extends _.CustomType {}
export function SameSitePolicy$Strict(): SameSitePolicy$;
export function SameSitePolicy$isStrict(value: any): value is SameSitePolicy$;

export class None extends _.CustomType {}
export function SameSitePolicy$None(): SameSitePolicy$;
export function SameSitePolicy$isNone(value: any): value is SameSitePolicy$;

export type SameSitePolicy$ = Lax | Strict | None;

export class Attributes extends _.CustomType {
  /** @deprecated */
  constructor(
    max_age: $option.Option$<number>,
    domain: $option.Option$<string>,
    path: $option.Option$<string>,
    secure: boolean,
    http_only: boolean,
    same_site: $option.Option$<SameSitePolicy$>
  );
  /** @deprecated */
  max_age: $option.Option$<number>;
  /** @deprecated */
  domain: $option.Option$<string>;
  /** @deprecated */
  path: $option.Option$<string>;
  /** @deprecated */
  secure: boolean;
  /** @deprecated */
  http_only: boolean;
  /** @deprecated */
  same_site: $option.Option$<SameSitePolicy$>;
}
export function Attributes$Attributes(
  max_age: $option.Option$<number>,
  domain: $option.Option$<string>,
  path: $option.Option$<string>,
  secure: boolean,
  http_only: boolean,
  same_site: $option.Option$<SameSitePolicy$>,
): Attributes$;
export function Attributes$isAttributes(value: any): value is Attributes$;
export function Attributes$Attributes$0(value: Attributes$): $option.Option$<
  number
>;
export function Attributes$Attributes$max_age(value: Attributes$): $option.Option$<
  number
>;
export function Attributes$Attributes$1(value: Attributes$): $option.Option$<
  string
>;
export function Attributes$Attributes$domain(value: Attributes$): $option.Option$<
  string
>;
export function Attributes$Attributes$2(value: Attributes$): $option.Option$<
  string
>;
export function Attributes$Attributes$path(value: Attributes$): $option.Option$<
  string
>;
export function Attributes$Attributes$3(value: Attributes$): boolean;
export function Attributes$Attributes$secure(value: Attributes$): boolean;
export function Attributes$Attributes$4(value: Attributes$): boolean;
export function Attributes$Attributes$http_only(value: Attributes$): boolean;
export function Attributes$Attributes$5(value: Attributes$): $option.Option$<
  SameSitePolicy$
>;
export function Attributes$Attributes$same_site(value: Attributes$): $option.Option$<
  SameSitePolicy$
>;

export type Attributes$ = Attributes;

export function defaults(scheme: $http.Scheme$): Attributes$;

export function set_header(name: string, value: string, attributes: Attributes$): string;

export function parse(cookie_string: string): _.List<[string, string]>;
