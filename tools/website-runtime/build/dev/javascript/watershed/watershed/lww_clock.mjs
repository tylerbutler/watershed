/// <reference types="./lww_clock.d.mts" />
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import { Ok, Error, CustomType as $CustomType } from "../gleam.mjs";

export class InvalidTimestamp extends $CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
export const ClockError$InvalidTimestamp = (value) =>
  new InvalidTimestamp(value);
export const ClockError$isInvalidTimestamp = (value) =>
  value instanceof InvalidTimestamp;
export const ClockError$InvalidTimestamp$value = (value) => value.value;
export const ClockError$InvalidTimestamp$0 = (value) => value.value;

export class ClockExhausted extends $CustomType {}
export const ClockError$ClockExhausted$const = new ClockExhausted();
export const ClockError$ClockExhausted = () => ClockError$ClockExhausted$const;
export const ClockError$isClockExhausted = (value) =>
  value instanceof ClockExhausted;

export const max_safe_timestamp = 9_007_199_254_740_991;

function validate(value) {
  let $ = (value < 0) || (value > max_safe_timestamp);
  if ($) {
    return new Error(new InvalidTimestamp(value));
  } else {
    return new Ok(undefined);
  }
}

/**
 * Return a timestamp greater than every observed timestamp and at least as
 * large as the current wall clock.
 */
export function next(last_seen, wall_clock) {
  let $ = validate(last_seen);
  let $1 = validate(wall_clock);
  if ($ instanceof Ok) {
    if ($1 instanceof Ok) {
      let $2 = last_seen === max_safe_timestamp;
      if ($2) {
        return new Error(ClockError$ClockExhausted$const);
      } else {
        return new Ok($int.max(wall_clock, last_seen + 1));
      }
    } else {
      return $1;
    }
  } else {
    return $;
  }
}
