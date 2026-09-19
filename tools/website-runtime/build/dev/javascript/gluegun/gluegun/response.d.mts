import type * as _ from "../gleam.d.mts";
import type * as $error from "../gluegun/error.d.mts";

declare class Response extends _.CustomType {
  /** @deprecated */
  constructor(
    status: number,
    headers: _.List<[string, string]>,
    body: _.BitArray,
    trailers: _.List<[string, string]>,
    informational: _.List<[number, _.List<[string, string]>]>
  );
  /** @deprecated */
  status: number;
  /** @deprecated */
  headers: _.List<[string, string]>;
  /** @deprecated */
  body: _.BitArray;
  /** @deprecated */
  trailers: _.List<[string, string]>;
  /** @deprecated */
  informational: _.List<[number, _.List<[string, string]>]>;
}

export type Response$ = Response;

export type Informational = [number, _.List<[string, string]>];

export function status(response: Response$): number;

export function headers(response: Response$): _.List<[string, string]>;

export function body(response: Response$): _.BitArray;

export function trailers(response: Response$): _.List<[string, string]>;

export function informational(response: Response$): _.List<
  [number, _.List<[string, string]>]
>;

export function new$(
  status: number,
  headers: _.List<[string, string]>,
  body: _.BitArray,
  trailers: _.List<[string, string]>
): Response$;

export function with_body(response: Response$, body: _.BitArray): Response$;

export function with_trailers(
  response: Response$,
  trailers: _.List<[string, string]>
): Response$;

export function with_informational(
  response: Response$,
  informational: _.List<[number, _.List<[string, string]>]>
): Response$;

export function body_text(response: Response$): _.Result<
  string,
  $error.GluegunError$
>;
