import type * as _ from "../../gleam.d.mts";

export type Ref$ = any;

export function from(value: any): Ref$;

export function equal(a: Ref$, b: Ref$): boolean;

export function equal_lists(xs: _.List<Ref$>, ys: _.List<Ref$>): boolean;
