import type * as _ from "../gleam.d.mts";

export class Get extends _.CustomType {}
export function Method$Get(): Method$;
export function Method$isGet(value: any): value is Method$;

export class Post extends _.CustomType {}
export function Method$Post(): Method$;
export function Method$isPost(value: any): value is Method$;

export class Patch extends _.CustomType {}
export function Method$Patch(): Method$;
export function Method$isPatch(value: any): value is Method$;

export class Put extends _.CustomType {}
export function Method$Put(): Method$;
export function Method$isPut(value: any): value is Method$;

export class Delete extends _.CustomType {}
export function Method$Delete(): Method$;
export function Method$isDelete(value: any): value is Method$;

export class Head extends _.CustomType {}
export function Method$Head(): Method$;
export function Method$isHead(value: any): value is Method$;

export class Options extends _.CustomType {}
export function Method$Options(): Method$;
export function Method$isOptions(value: any): value is Method$;

export class Trace extends _.CustomType {}
export function Method$Trace(): Method$;
export function Method$isTrace(value: any): value is Method$;

export class Connect extends _.CustomType {}
export function Method$Connect(): Method$;
export function Method$isConnect(value: any): value is Method$;

export class Other extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function Method$Other($0: string): Method$;
export function Method$isOther(value: any): value is Method$;
export function Method$Other$0(value: Method$): string;

export type Method$ = Get | Post | Patch | Put | Delete | Head | Options | Trace | Connect | Other;

export class Http extends _.CustomType {}
export function Scheme$Http(): Scheme$;
export function Scheme$isHttp(value: any): value is Scheme$;

export class Https extends _.CustomType {}
export function Scheme$Https(): Scheme$;
export function Scheme$isHttps(value: any): value is Scheme$;

export type Scheme$ = Http | Https;

export class MultipartHeaders extends _.CustomType {
  /** @deprecated */
  constructor(headers: _.List<[string, string]>, remaining: _.BitArray);
  /** @deprecated */
  headers: _.List<[string, string]>;
  /** @deprecated */
  remaining: _.BitArray;
}
export function MultipartHeaders$MultipartHeaders(
  headers: _.List<[string, string]>,
  remaining: _.BitArray,
): MultipartHeaders$;
export function MultipartHeaders$isMultipartHeaders(
  value: any,
): value is MultipartHeaders$;
export function MultipartHeaders$MultipartHeaders$0(value: MultipartHeaders$): _.List<
  [string, string]
>;
export function MultipartHeaders$MultipartHeaders$headers(value: MultipartHeaders$): _.List<
  [string, string]
>;
export function MultipartHeaders$MultipartHeaders$1(value: MultipartHeaders$): _.BitArray;
export function MultipartHeaders$MultipartHeaders$remaining(
  value: MultipartHeaders$,
): _.BitArray;

export class MoreRequiredForHeaders extends _.CustomType {
  /** @deprecated */
  constructor(
    continuation: (x0: _.BitArray) => _.Result<MultipartHeaders$, undefined>
  );
  /** @deprecated */
  continuation: (x0: _.BitArray) => _.Result<MultipartHeaders$, undefined>;
}
export function MultipartHeaders$MoreRequiredForHeaders(
  continuation: (x0: _.BitArray) => _.Result<MultipartHeaders$, undefined>,
): MultipartHeaders$;
export function MultipartHeaders$isMoreRequiredForHeaders(
  value: any,
): value is MultipartHeaders$;
export function MultipartHeaders$MoreRequiredForHeaders$0(value: MultipartHeaders$): (
  x0: _.BitArray
) => _.Result<MultipartHeaders$, undefined>;
export function MultipartHeaders$MoreRequiredForHeaders$continuation(value: MultipartHeaders$): (
  x0: _.BitArray
) => _.Result<MultipartHeaders$, undefined>;

export type MultipartHeaders$ = MultipartHeaders | MoreRequiredForHeaders;

export class MultipartBody extends _.CustomType {
  /** @deprecated */
  constructor(chunk: _.BitArray, done: boolean, remaining: _.BitArray);
  /** @deprecated */
  chunk: _.BitArray;
  /** @deprecated */
  done: boolean;
  /** @deprecated */
  remaining: _.BitArray;
}
export function MultipartBody$MultipartBody(
  chunk: _.BitArray,
  done: boolean,
  remaining: _.BitArray,
): MultipartBody$;
export function MultipartBody$isMultipartBody(
  value: any,
): value is MultipartBody$;
export function MultipartBody$MultipartBody$0(value: MultipartBody$): _.BitArray;
export function MultipartBody$MultipartBody$chunk(
  value: MultipartBody$,
): _.BitArray;
export function MultipartBody$MultipartBody$1(value: MultipartBody$): boolean;
export function MultipartBody$MultipartBody$done(value: MultipartBody$): boolean;
export function MultipartBody$MultipartBody$2(
  value: MultipartBody$,
): _.BitArray;
export function MultipartBody$MultipartBody$remaining(value: MultipartBody$): _.BitArray;

export class MoreRequiredForBody extends _.CustomType {
  /** @deprecated */
  constructor(
    chunk: _.BitArray,
    continuation: (x0: _.BitArray) => _.Result<MultipartBody$, undefined>
  );
  /** @deprecated */
  chunk: _.BitArray;
  /** @deprecated */
  continuation: (x0: _.BitArray) => _.Result<MultipartBody$, undefined>;
}
export function MultipartBody$MoreRequiredForBody(
  chunk: _.BitArray,
  continuation: (x0: _.BitArray) => _.Result<MultipartBody$, undefined>,
): MultipartBody$;
export function MultipartBody$isMoreRequiredForBody(
  value: any,
): value is MultipartBody$;
export function MultipartBody$MoreRequiredForBody$0(value: MultipartBody$): _.BitArray;
export function MultipartBody$MoreRequiredForBody$chunk(
  value: MultipartBody$,
): _.BitArray;
export function MultipartBody$MoreRequiredForBody$1(value: MultipartBody$): (
  x0: _.BitArray
) => _.Result<MultipartBody$, undefined>;
export function MultipartBody$MoreRequiredForBody$continuation(value: MultipartBody$): (
  x0: _.BitArray
) => _.Result<MultipartBody$, undefined>;

export type MultipartBody$ = MultipartBody | MoreRequiredForBody;

export function MultipartBody$chunk(value: MultipartBody$): _.BitArray;

export class ContentDisposition extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string, parameters: _.List<[string, string]>);
  /** @deprecated */
  0: string;
  /** @deprecated */
  parameters: _.List<[string, string]>;
}
export function ContentDisposition$ContentDisposition(
  $0: string,
  parameters: _.List<[string, string]>,
): ContentDisposition$;
export function ContentDisposition$isContentDisposition(
  value: any,
): value is ContentDisposition$;
export function ContentDisposition$ContentDisposition$0(value: ContentDisposition$): string;
export function ContentDisposition$ContentDisposition$1(
  value: ContentDisposition$,
): _.List<[string, string]>;
export function ContentDisposition$ContentDisposition$parameters(value: ContentDisposition$): _.List<
  [string, string]
>;

export type ContentDisposition$ = ContentDisposition;

export type Header = [string, string];

export function parse_method(method: string): _.Result<Method$, undefined>;

export function method_to_string(method: Method$): string;

export function scheme_to_string(scheme: Scheme$): string;

export function scheme_from_string(scheme: string): _.Result<Scheme$, undefined>;

export function parse_multipart_headers(data: _.BitArray, boundary: string): _.Result<
  MultipartHeaders$,
  undefined
>;

export function parse_multipart_body(data: _.BitArray, boundary: string): _.Result<
  MultipartBody$,
  undefined
>;

export function parse_content_disposition(header: string): _.Result<
  ContentDisposition$,
  undefined
>;
