import type * as $dynamic from "../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "./gleam.d.mts";

export class Errored extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $dynamic.Dynamic$);
  /** @deprecated */
  0: $dynamic.Dynamic$;
}
export function Exception$Errored($0: $dynamic.Dynamic$): Exception$;
export function Exception$isErrored(value: any): value is Exception$;
export function Exception$Errored$0(value: Exception$): $dynamic.Dynamic$;

export class Thrown extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $dynamic.Dynamic$);
  /** @deprecated */
  0: $dynamic.Dynamic$;
}
export function Exception$Thrown($0: $dynamic.Dynamic$): Exception$;
export function Exception$isThrown(value: any): value is Exception$;
export function Exception$Thrown$0(value: Exception$): $dynamic.Dynamic$;

export class Exited extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $dynamic.Dynamic$);
  /** @deprecated */
  0: $dynamic.Dynamic$;
}
export function Exception$Exited($0: $dynamic.Dynamic$): Exception$;
export function Exception$isExited(value: any): value is Exception$;
export function Exception$Exited$0(value: Exception$): $dynamic.Dynamic$;

export type Exception$ = Errored | Thrown | Exited;

export function rescue<HHE>(body: () => HHE): _.Result<HHE, Exception$>;

export function defer<HHI>(cleanup: () => any, body: () => HHI): HHI;

export function on_crash<HHK>(cleanup: () => any, body: () => HHK): HHK;
