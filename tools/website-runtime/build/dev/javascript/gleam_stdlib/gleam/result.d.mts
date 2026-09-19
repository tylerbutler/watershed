import type * as _ from "../gleam.d.mts";

export function is_ok(result: _.Result<any, any>): boolean;

export function is_error(result: _.Result<any, any>): boolean;

export function map<CMY, CMZ, CNC>(
  result: _.Result<CMY, CMZ>,
  fun: (x0: CMY) => CNC
): _.Result<CNC, CMZ>;

export function map_error<CNF, CNG, CNJ>(
  result: _.Result<CNF, CNG>,
  fun: (x0: CNG) => CNJ
): _.Result<CNF, CNJ>;

export function flatten<CNM, CNN>(result: _.Result<_.Result<CNM, CNN>, CNN>): _.Result<
  CNM,
  CNN
>;

export function try$<CNU, CNV, CNY>(
  result: _.Result<CNU, CNV>,
  fun: (x0: CNU) => _.Result<CNY, CNV>
): _.Result<CNY, CNV>;

export function unwrap<COD>(result: _.Result<COD, any>, default$: COD): COD;

export function lazy_unwrap<COH>(
  result: _.Result<COH, any>,
  default$: () => COH
): COH;

export function unwrap_error<COM>(result: _.Result<any, COM>, default$: COM): COM;

export function or<COP, COQ>(
  first: _.Result<COP, COQ>,
  second: _.Result<COP, COQ>
): _.Result<COP, COQ>;

export function lazy_or<COX, COY>(
  first: _.Result<COX, COY>,
  second: () => _.Result<COX, COY>
): _.Result<COX, COY>;

export function all<CPF, CPG>(results: _.List<_.Result<CPF, CPG>>): _.Result<
  _.List<CPF>,
  CPG
>;

export function partition<CPN, CPO>(results: _.List<_.Result<CPN, CPO>>): [
  _.List<CPN>,
  _.List<CPO>
];

export function replace<CQD, CQG>(result: _.Result<any, CQD>, value: CQG): _.Result<
  CQG,
  CQD
>;

export function replace_error<CQJ, CQN>(result: _.Result<CQJ, any>, error: CQN): _.Result<
  CQJ,
  CQN
>;

export function values<CQQ>(results: _.List<_.Result<CQQ, any>>): _.List<CQQ>;

export function try_recover<CQW, CQX, CRA>(
  result: _.Result<CQW, CQX>,
  fun: (x0: CQX) => _.Result<CQW, CRA>
): _.Result<CQW, CRA>;
