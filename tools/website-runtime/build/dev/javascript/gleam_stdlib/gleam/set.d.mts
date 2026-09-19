import type * as _ from "../gleam.d.mts";
import type * as $dict from "../gleam/dict.d.mts";

declare class Set<CVN> extends _.CustomType {
  /** @deprecated */
  constructor(dict: $dict.Dict$<CVN, undefined>);
  /** @deprecated */
  dict: $dict.Dict$<CVN, undefined>;
}

export type Set$<CVN> = Set<CVN>;

export function new$(): Set$<any>;

export function size(set: Set$<any>): number;

export function is_empty(set: Set$<any>): boolean;

export function insert<CVU>(set: Set$<CVU>, member: CVU): Set$<CVU>;

export function contains<CVX>(set: Set$<CVX>, member: CVX): boolean;

export function delete$<CVZ>(set: Set$<CVZ>, member: CVZ): Set$<CVZ>;

export function to_list<CWC>(set: Set$<CWC>): _.List<CWC>;

export function from_list<CWF>(members: _.List<CWF>): Set$<CWF>;

export function fold<CWI, CWK>(
  set: Set$<CWI>,
  initial: CWK,
  reducer: (x0: CWK, x1: CWI) => CWK
): CWK;

export function filter<CWL>(set: Set$<CWL>, predicate: (x0: CWL) => boolean): Set$<
  CWL
>;

export function map<CWO, CWQ>(set: Set$<CWO>, fun: (x0: CWO) => CWQ): Set$<CWQ>;

export function drop<CWS>(set: Set$<CWS>, disallowed: _.List<CWS>): Set$<CWS>;

export function take<CWW>(set: Set$<CWW>, desired: _.List<CWW>): Set$<CWW>;

export function union<CXA>(first: Set$<CXA>, second: Set$<CXA>): Set$<CXA>;

export function intersection<CXJ>(first: Set$<CXJ>, second: Set$<CXJ>): Set$<
  CXJ
>;

export function difference<CXN>(first: Set$<CXN>, second: Set$<CXN>): Set$<CXN>;

export function is_subset<CXR>(first: Set$<CXR>, second: Set$<CXR>): boolean;

export function is_disjoint<CXU>(first: Set$<CXU>, second: Set$<CXU>): boolean;

export function symmetric_difference<CXX>(first: Set$<CXX>, second: Set$<CXX>): Set$<
  CXX
>;

export function each<CYB>(set: Set$<CYB>, fun: (x0: CYB) => any): undefined;
