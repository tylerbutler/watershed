import type * as _ from "../../gleam.d.mts";
import type * as $cookie from "../../gleam/http/cookie.d.mts";

export class Response<IGQ> extends _.CustomType {
  /** @deprecated */
  constructor(status: number, headers: _.List<[string, string]>, body: IGQ);
  /** @deprecated */
  status: number;
  /** @deprecated */
  headers: _.List<[string, string]>;
  /** @deprecated */
  body: IGQ;
}
export function Response$Response<IGQ>(
  status: number,
  headers: _.List<[string, string]>,
  body: IGQ,
): Response$<IGQ>;
export function Response$isResponse<IGQ>(
  value: any,
): value is Response$<unknown>;
export function Response$Response$0<IGQ>(value: Response$<IGQ>): number;
export function Response$Response$status<IGQ>(value: Response$<IGQ>): number;
export function Response$Response$1<IGQ>(value: Response$<IGQ>): _.List<
  [string, string]
>;
export function Response$Response$headers<IGQ>(value: Response$<IGQ>): _.List<
  [string, string]
>;
export function Response$Response$2<IGQ>(value: Response$<IGQ>): IGQ;
export function Response$Response$body<IGQ>(value: Response$<IGQ>): IGQ;

export type Response$<IGQ> = Response<IGQ>;

export function set_body<IHN>(response: Response$<any>, body: IHN): Response$<
  IHN
>;

export function try_map<IGR, IGT, IGU>(
  response: Response$<IGR>,
  transform: (x0: IGR) => _.Result<IGT, IGU>
): _.Result<Response$<IGT>, IGU>;

export function new$(status: number): Response$<string>;

export function get_header(response: Response$<any>, key: string): _.Result<
  string,
  undefined
>;

export function set_header<IHF>(
  response: Response$<IHF>,
  key: string,
  value: string
): Response$<IHF>;

export function prepend_header<IHI>(
  response: Response$<IHI>,
  key: string,
  value: string
): Response$<IHI>;

export function map<IHP, IHR>(
  response: Response$<IHP>,
  transform: (x0: IHP) => IHR
): Response$<IHR>;

export function redirect(uri: string): Response$<string>;

export function get_cookies(resp: Response$<any>): _.List<[string, string]>;

export function set_cookie<IHX>(
  response: Response$<IHX>,
  name: string,
  value: string,
  attributes: $cookie.Attributes$
): Response$<IHX>;

export function expire_cookie<IIA>(
  response: Response$<IIA>,
  name: string,
  attributes: $cookie.Attributes$
): Response$<IIA>;
