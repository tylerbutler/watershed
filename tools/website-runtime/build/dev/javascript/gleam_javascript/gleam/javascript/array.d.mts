import type * as _ from "../../gleam.d.mts";

export type Array$<INM> = any;

export function fold_right<IOC, IOE>(
  over: Array$<IOC>,
  from: IOE,
  with$: (x0: IOE, x1: IOC) => IOE
): IOE;

export function to_list<INN>(items: Array$<INN>): _.List<INN>;

export function from_list<INQ>(a: _.List<INQ>): Array$<INQ>;

export function size(a: Array$<any>): number;

export function map<INV, INX>(a: Array$<INV>, with$: (x0: INV) => INX): Array$<
  INX
>;

export function fold<INZ, IOB>(
  over: Array$<INZ>,
  from: IOB,
  with$: (x0: IOB, x1: INZ) => IOB
): IOB;

export function get<IOF>(a: Array$<IOF>, b: number): _.Result<IOF, undefined>;
