import type * as _ from "../gleam.d.mts";

declare class Policy extends _.CustomType {
  /** @deprecated */
  constructor(threshold: number, jitter_milliseconds: number);
  /** @deprecated */
  threshold: number;
  /** @deprecated */
  jitter_milliseconds: number;
}

export type Policy$ = Policy;

export function policy(): Policy$;

export function with_threshold(policy: Policy$, threshold: number): Policy$;

export function with_jitter_milliseconds(
  policy: Policy$,
  jitter_milliseconds: number
): Policy$;

export function policy_threshold(policy: Policy$): number;

export function policy_jitter_milliseconds(policy: Policy$): number;
