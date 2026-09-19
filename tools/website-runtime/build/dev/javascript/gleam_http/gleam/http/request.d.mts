import type * as $option from "../../../gleam_stdlib/gleam/option.d.mts";
import type * as $uri from "../../../gleam_stdlib/gleam/uri.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $http from "../../gleam/http.d.mts";

export class Request<HWM> extends _.CustomType {
  /** @deprecated */
  constructor(
    method: $http.Method$,
    headers: _.List<[string, string]>,
    body: HWM,
    scheme: $http.Scheme$,
    host: string,
    port: $option.Option$<number>,
    path: string,
    query: $option.Option$<string>
  );
  /** @deprecated */
  method: $http.Method$;
  /** @deprecated */
  headers: _.List<[string, string]>;
  /** @deprecated */
  body: HWM;
  /** @deprecated */
  scheme: $http.Scheme$;
  /** @deprecated */
  host: string;
  /** @deprecated */
  port: $option.Option$<number>;
  /** @deprecated */
  path: string;
  /** @deprecated */
  query: $option.Option$<string>;
}
export function Request$Request<HWM>(
  method: $http.Method$,
  headers: _.List<[string, string]>,
  body: HWM,
  scheme: $http.Scheme$,
  host: string,
  port: $option.Option$<number>,
  path: string,
  query: $option.Option$<string>,
): Request$<HWM>;
export function Request$isRequest<HWM>(value: any): value is Request$<unknown>;
export function Request$Request$0<HWM>(value: Request$<HWM>): $http.Method$;
export function Request$Request$method<HWM>(value: Request$<HWM>): $http.Method$;
export function Request$Request$1<HWM>(
  value: Request$<HWM>,
): _.List<[string, string]>;
export function Request$Request$headers<HWM>(value: Request$<HWM>): _.List<
  [string, string]
>;
export function Request$Request$2<HWM>(value: Request$<HWM>): HWM;
export function Request$Request$body<HWM>(value: Request$<HWM>): HWM;
export function Request$Request$3<HWM>(value: Request$<HWM>): $http.Scheme$;
export function Request$Request$scheme<HWM>(value: Request$<HWM>): $http.Scheme$;
export function Request$Request$4<HWM>(
  value: Request$<HWM>,
): string;
export function Request$Request$host<HWM>(value: Request$<HWM>): string;
export function Request$Request$5<HWM>(value: Request$<HWM>): $option.Option$<
  number
>;
export function Request$Request$port<HWM>(value: Request$<HWM>): $option.Option$<
  number
>;
export function Request$Request$6<HWM>(value: Request$<HWM>): string;
export function Request$Request$path<HWM>(value: Request$<HWM>): string;
export function Request$Request$7<HWM>(value: Request$<HWM>): $option.Option$<
  string
>;
export function Request$Request$query<HWM>(value: Request$<HWM>): $option.Option$<
  string
>;

export type Request$<HWM> = Request<HWM>;

export function to_uri(request: Request$<any>): $uri.Uri$;

export function from_uri(uri: $uri.Uri$): _.Result<Request$<string>, undefined>;

export function get_header(request: Request$<any>, key: string): _.Result<
  string,
  undefined
>;

export function set_header<HWW>(
  request: Request$<HWW>,
  key: string,
  value: string
): Request$<HWW>;

export function prepend_header<HWZ>(
  request: Request$<HWZ>,
  key: string,
  value: string
): Request$<HWZ>;

export function set_body<HXE>(req: Request$<any>, body: HXE): Request$<HXE>;

export function map<HXG, HXI>(
  request: Request$<HXG>,
  transform: (x0: HXG) => HXI
): Request$<HXI>;

export function path_segments(request: Request$<any>): _.List<string>;

export function get_query(request: Request$<any>): _.Result<
  _.List<[string, string]>,
  undefined
>;

export function set_query<HXS>(
  req: Request$<HXS>,
  query: _.List<[string, string]>
): Request$<HXS>;

export function set_method<HXW>(req: Request$<HXW>, method: $http.Method$): Request$<
  HXW
>;

export function new$(): Request$<string>;

export function to(url: string): _.Result<Request$<string>, undefined>;

export function set_scheme<HYD>(req: Request$<HYD>, scheme: $http.Scheme$): Request$<
  HYD
>;

export function set_host<HYG>(req: Request$<HYG>, host: string): Request$<HYG>;

export function set_port<HYJ>(req: Request$<HYJ>, port: number): Request$<HYJ>;

export function set_path<HYM>(req: Request$<HYM>, path: string): Request$<HYM>;

export function set_cookie<HYP>(req: Request$<HYP>, name: string, value: string): Request$<
  HYP
>;

export function get_cookies(req: Request$<any>): _.List<[string, string]>;

export function remove_cookie<HYV>(req: Request$<HYV>, name: string): Request$<
  HYV
>;
