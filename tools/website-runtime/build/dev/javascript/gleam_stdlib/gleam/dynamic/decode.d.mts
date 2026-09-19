import type * as _ from "../../gleam.d.mts";
import type * as $dict from "../../gleam/dict.d.mts";
import type * as $dynamic from "../../gleam/dynamic.d.mts";
import type * as $option from "../../gleam/option.d.mts";

export class DecodeError extends _.CustomType {
  /** @deprecated */
  constructor(expected: string, found: string, path: _.List<string>);
  /** @deprecated */
  expected: string;
  /** @deprecated */
  found: string;
  /** @deprecated */
  path: _.List<string>;
}
export function DecodeError$DecodeError(
  expected: string,
  found: string,
  path: _.List<string>,
): DecodeError$;
export function DecodeError$isDecodeError(value: any): value is DecodeError$;
export function DecodeError$DecodeError$0(value: DecodeError$): string;
export function DecodeError$DecodeError$expected(value: DecodeError$): string;
export function DecodeError$DecodeError$1(value: DecodeError$): string;
export function DecodeError$DecodeError$found(value: DecodeError$): string;
export function DecodeError$DecodeError$2(value: DecodeError$): _.List<string>;
export function DecodeError$DecodeError$path(value: DecodeError$): _.List<
  string
>;

export type DecodeError$ = DecodeError;

declare class Decoder<BVQ> extends _.CustomType {
  /** @deprecated */
  constructor(function$: (x0: $dynamic.Dynamic$) => [BVQ, _.List<DecodeError$>]);
  /** @deprecated */
  function: (x0: $dynamic.Dynamic$) => [BVQ, _.List<DecodeError$>];
}

export type Decoder$<BVQ> = Decoder<BVQ>;

export type Dynamic = $dynamic.Dynamic$;

export const dynamic: Decoder$<$dynamic.Dynamic$>;

export const float: Decoder$<number>;

export const int: Decoder$<number>;

export const bit_array: Decoder$<_.BitArray>;

export const string: Decoder$<string>;

export const bool: Decoder$<boolean>;

export function run<BVY>(data: $dynamic.Dynamic$, decoder: Decoder$<BVY>): _.Result<
  BVY,
  _.List<DecodeError$>
>;

export function map<BZW, BZY>(
  decoder: Decoder$<BZW>,
  transformer: (x0: BZW) => BZY
): Decoder$<BZY>;

export function one_of<CAN>(
  first: Decoder$<CAN>,
  alternatives: _.List<Decoder$<CAN>>
): Decoder$<CAN>;

export function list<BYL>(inner: Decoder$<BYL>): Decoder$<_.List<BYL>>;

export function subfield<BVT, BVV>(
  field_path: _.List<any>,
  field_decoder: Decoder$<BVT>,
  next: (x0: BVT) => Decoder$<BVV>
): Decoder$<BVV>;

export function at<BWF>(path: _.List<any>, inner: Decoder$<BWF>): Decoder$<BWF>;

export function success<BWZ>(data: BWZ): Decoder$<BWZ>;

export function decode_error(expected: string, found: $dynamic.Dynamic$): _.List<
  DecodeError$
>;

export function field<BXD, BXF>(
  field_name: any,
  field_decoder: Decoder$<BXD>,
  next: (x0: BXD) => Decoder$<BXF>
): Decoder$<BXF>;

export function optional_field<BXJ, BXL>(
  key: any,
  default$: BXJ,
  field_decoder: Decoder$<BXJ>,
  next: (x0: BXJ) => Decoder$<BXL>
): Decoder$<BXL>;

export function optionally_at<BXQ>(
  path: _.List<any>,
  default$: BXQ,
  inner: Decoder$<BXQ>
): Decoder$<BXQ>;

export function dict<BYX, BYZ>(key: Decoder$<BYX>, value: Decoder$<BYZ>): Decoder$<
  $dict.Dict$<BYX, BYZ>
>;

export function optional<BZS>(inner: Decoder$<BZS>): Decoder$<
  $option.Option$<BZS>
>;

export function map_errors<CAA>(
  decoder: Decoder$<CAA>,
  transformer: (x0: _.List<DecodeError$>) => _.List<DecodeError$>
): Decoder$<CAA>;

export function collapse_errors<CAF>(decoder: Decoder$<CAF>, name: string): Decoder$<
  CAF
>;

export function then$<CAI, CAK>(
  decoder: Decoder$<CAI>,
  next: (x0: CAI) => Decoder$<CAK>
): Decoder$<CAK>;

export function failure<CAX>(placeholder: CAX, name: string): Decoder$<CAX>;

export function new_primitive_decoder<CAZ>(
  name: string,
  decoding_function: (x0: $dynamic.Dynamic$) => _.Result<CAZ, CAZ>
): Decoder$<CAZ>;

export function recursive<CBD>(inner: () => Decoder$<CBD>): Decoder$<CBD>;
