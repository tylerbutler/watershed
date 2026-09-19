import type * as $request from "../../gleam_http/gleam/http/request.d.mts";
import type * as $response from "../../gleam_http/gleam/http/response.d.mts";
import type * as $promise from "../../gleam_javascript/gleam/javascript/promise.d.mts";
import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $form_data from "../gleam/fetch/form_data.d.mts";

export class NetworkError extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function FetchError$NetworkError($0: string): FetchError$;
export function FetchError$isNetworkError(value: any): value is FetchError$;
export function FetchError$NetworkError$0(value: FetchError$): string;

export class UnableToReadBody extends _.CustomType {}
export function FetchError$UnableToReadBody(): FetchError$;
export function FetchError$isUnableToReadBody(value: any): value is FetchError$;

export class InvalidJsonBody extends _.CustomType {}
export function FetchError$InvalidJsonBody(): FetchError$;
export function FetchError$isInvalidJsonBody(value: any): value is FetchError$;

export type FetchError$ = NetworkError | UnableToReadBody | InvalidJsonBody;

export type FetchBody$ = any;

export type FetchRequest$ = any;

export type FetchResponse$ = any;

export type BodyReader$ = any;

export function raw_send(a: FetchRequest$): $promise.Promise$<
  _.Result<FetchResponse$, FetchError$>
>;

export function from_fetch_response(a: FetchResponse$): $response.Response$<
  FetchBody$
>;

export function to_fetch_request(a: $request.Request$<string>): FetchRequest$;

export function send(request: $request.Request$<string>): $promise.Promise$<
  _.Result<$response.Response$<FetchBody$>, FetchError$>
>;

export function form_data_to_fetch_request(
  a: $request.Request$<$form_data.FormData$>
): FetchRequest$;

export function send_form_data(request: $request.Request$<$form_data.FormData$>): $promise.Promise$<
  _.Result<$response.Response$<FetchBody$>, FetchError$>
>;

export function bitarray_request_to_fetch_request(
  a: $request.Request$<_.BitArray>
): FetchRequest$;

export function send_bits(request: $request.Request$<_.BitArray>): $promise.Promise$<
  _.Result<$response.Response$<FetchBody$>, FetchError$>
>;

export function read_bytes_body(a: $response.Response$<FetchBody$>): $promise.Promise$<
  _.Result<$response.Response$<_.BitArray>, FetchError$>
>;

export function read_text_body(a: $response.Response$<FetchBody$>): $promise.Promise$<
  _.Result<$response.Response$<string>, FetchError$>
>;

export function read_json_body(a: $response.Response$<FetchBody$>): $promise.Promise$<
  _.Result<$response.Response$<$dynamic.Dynamic$>, FetchError$>
>;

export function stream_body(response: $response.Response$<FetchBody$>): _.Result<
  BodyReader$,
  FetchError$
>;

export function read_chunk(reader: BodyReader$): $promise.Promise$<
  _.Result<$option.Option$<_.BitArray>, FetchError$>
>;
