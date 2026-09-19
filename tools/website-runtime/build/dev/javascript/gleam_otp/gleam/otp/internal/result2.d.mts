import type * as _ from "../../../gleam.d.mts";

export class Ok<EPV, EPW> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: EPV, argument$1: EPW);
  /** @deprecated */
  0: EPV;
  /** @deprecated */
  1: EPW;
}
export function Result2$Ok<EPV, EPW, EPX>(
  $0: EPV,
  $1: EPW,
): Result2$<EPV, EPW, EPX>;
export function Result2$isOk<EPV, EPW, EPX>(
  value: any,
): value is Result2$<unknown, unknown, unknown>;
export function Result2$Ok$0<EPV, EPW, EPX>(value: Result2$<EPV, EPW, EPX>): EPV;
export function Result2$Ok$1<EPV, EPW, EPX>(
  value: Result2$<EPV, EPW, EPX>,
): EPW;

export class Error<EPX> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: EPX);
  /** @deprecated */
  0: EPX;
}
export function Result2$Error<EPV, EPW, EPX>($0: EPX): Result2$<EPV, EPW, EPX>;
export function Result2$isError<EPV, EPW, EPX>(
  value: any,
): value is Result2$<unknown, unknown, unknown>;
export function Result2$Error$0<EPV, EPW, EPX>(value: Result2$<EPV, EPW, EPX>): EPX;

export type Result2$<EPV, EPW, EPX> = Ok<EPV, EPW> | Error<EPX>;
