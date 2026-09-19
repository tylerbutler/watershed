import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $array from "../../gleam/javascript/array.d.mts";

export type Promise$<IOQ> = any;

export function new$<IOR>(a: (x0: (x0: IOR) => undefined) => undefined): Promise$<
  IOR
>;

export function start<IOT>(): [Promise$<IOT>, (x0: IOT) => undefined];

export function resolve<IOV>(a: IOV): Promise$<IOV>;

export function rescue<IOX>(a: Promise$<IOX>, b: (x0: $dynamic.Dynamic$) => IOX): Promise$<
  IOX
>;

export function await$<IPA, IPC>(
  a: Promise$<IPA>,
  b: (x0: IPA) => Promise$<IPC>
): Promise$<IPC>;

export function map<IPF, IPH>(a: Promise$<IPF>, b: (x0: IPF) => IPH): Promise$<
  IPH
>;

export function tap<IPJ>(promise: Promise$<IPJ>, callback: (x0: IPJ) => any): Promise$<
  IPJ
>;

export function map_try<IPN, IPO, IPS>(
  promise: Promise$<_.Result<IPN, IPO>>,
  callback: (x0: IPN) => _.Result<IPS, IPO>
): Promise$<_.Result<IPS, IPO>>;

export function try_await<IPY, IPZ, IQD>(
  promise: Promise$<_.Result<IPY, IPZ>>,
  callback: (x0: IPY) => Promise$<_.Result<IQD, IPZ>>
): Promise$<_.Result<IQD, IPZ>>;

export function await_array<IQK>(a: $array.Array$<Promise$<IQK>>): Promise$<
  $array.Array$<IQK>
>;

export function await_list<IQP>(xs: _.List<Promise$<IQP>>): Promise$<
  _.List<IQP>
>;

export function race_list<IQZ>(a: _.List<Promise$<IQZ>>): Promise$<IQZ>;

export function race_array<IRD>(a: $array.Array$<Promise$<IRD>>): Promise$<IRD>;

export function wait(delay: number): Promise$<undefined>;
