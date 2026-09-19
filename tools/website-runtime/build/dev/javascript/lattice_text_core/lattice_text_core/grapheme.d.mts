import type * as _ from "../gleam.d.mts";

export class RangeOutOfBounds extends _.CustomType {
  /** @deprecated */
  constructor(start: number, end: number, length: number);
  /** @deprecated */
  start: number;
  /** @deprecated */
  end: number;
  /** @deprecated */
  length: number;
}
export function RangeError$RangeOutOfBounds(
  start: number,
  end: number,
  length: number,
): RangeError$;
export function RangeError$isRangeOutOfBounds(value: any): value is RangeError$;
export function RangeError$RangeOutOfBounds$0(value: RangeError$): number;
export function RangeError$RangeOutOfBounds$start(value: RangeError$): number;
export function RangeError$RangeOutOfBounds$1(value: RangeError$): number;
export function RangeError$RangeOutOfBounds$end(value: RangeError$): number;
export function RangeError$RangeOutOfBounds$2(value: RangeError$): number;
export function RangeError$RangeOutOfBounds$length(value: RangeError$): number;

export type RangeError$ = RangeOutOfBounds;

export function validate_range(start: number, end: number, length: number): _.Result<
  undefined,
  RangeError$
>;

export function value(graphemes: _.List<string>): string;

export function slice(graphemes: _.List<string>, start: number, end: number): string;

export function insert_graphemes<OOR, OOT>(
  graphemes: _.List<string>,
  state: OOR,
  index: number,
  length: (x0: OOR) => number,
  insert_many: (x0: OOR, x1: number, x2: _.List<string>) => _.Result<
    [OOR, OOR],
    OOT
  >,
  index_out_of_bounds: (x0: number, x1: number) => OOT
): _.Result<[OOR, OOR], OOT>;

export function delete_graphemes<OOY, OOZ>(
  state: OOY,
  start: number,
  end: number,
  delete$: (x0: OOY, x1: number) => _.Result<[OOY, OOY], OOZ>,
  merge: (x0: OOY, x1: OOY) => OOY
): _.Result<[OOY, OOY], OOZ>;
