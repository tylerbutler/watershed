import type * as _ from "../gleam.d.mts";

export class InvalidTimestamp extends _.CustomType {
  /** @deprecated */
  constructor(value: number);
  /** @deprecated */
  value: number;
}
export function ClockError$InvalidTimestamp(value: number): ClockError$;
export function ClockError$isInvalidTimestamp(value: any): value is ClockError$;
export function ClockError$InvalidTimestamp$0(value: ClockError$): number;
export function ClockError$InvalidTimestamp$value(value: ClockError$): number;

export class ClockExhausted extends _.CustomType {}
export function ClockError$ClockExhausted(): ClockError$;
export function ClockError$isClockExhausted(value: any): value is ClockError$;

export type ClockError$ = InvalidTimestamp | ClockExhausted;

export const max_safe_timestamp: number;

export function next(last_seen: number, wall_clock: number): _.Result<
  number,
  ClockError$
>;
