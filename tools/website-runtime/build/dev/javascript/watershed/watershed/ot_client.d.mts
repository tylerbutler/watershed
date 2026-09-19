import type * as $option from "../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../gleam.d.mts";

export class LogEntry<AJCA> extends _.CustomType {
  /** @deprecated */
  constructor(sequence_number: number, operation: AJCA);
  /** @deprecated */
  sequence_number: number;
  /** @deprecated */
  operation: AJCA;
}
export function LogEntry$LogEntry<AJCA>(
  sequence_number: number,
  operation: AJCA,
): LogEntry$<AJCA>;
export function LogEntry$isLogEntry<AJCA>(
  value: any,
): value is LogEntry$<unknown>;
export function LogEntry$LogEntry$0<AJCA>(value: LogEntry$<AJCA>): number;
export function LogEntry$LogEntry$sequence_number<AJCA>(value: LogEntry$<AJCA>): number;
export function LogEntry$LogEntry$1<AJCA>(
  value: LogEntry$<AJCA>,
): AJCA;
export function LogEntry$LogEntry$operation<AJCA>(value: LogEntry$<AJCA>): AJCA;

export type LogEntry$<AJCA> = LogEntry<AJCA>;

export class Idle extends _.CustomType {}
export function Pending$Idle<AJCB>(): Pending$<AJCB>;
export function Pending$isIdle<AJCB>(value: any): value is Pending$<unknown>;

export class InFlight<AJCB> extends _.CustomType {
  /** @deprecated */
  constructor(operation: AJCB);
  /** @deprecated */
  operation: AJCB;
}
export function Pending$InFlight<AJCB>(operation: AJCB): Pending$<AJCB>;
export function Pending$isInFlight<AJCB>(
  value: any,
): value is Pending$<unknown>;
export function Pending$InFlight$0<AJCB>(value: Pending$<AJCB>): AJCB;
export function Pending$InFlight$operation<AJCB>(value: Pending$<AJCB>): AJCB;

export class InFlightAndBuffered<AJCB> extends _.CustomType {
  /** @deprecated */
  constructor(operation: AJCB, buffered: AJCB);
  /** @deprecated */
  operation: AJCB;
  /** @deprecated */
  buffered: AJCB;
}
export function Pending$InFlightAndBuffered<AJCB>(
  operation: AJCB,
  buffered: AJCB,
): Pending$<AJCB>;
export function Pending$isInFlightAndBuffered<AJCB>(
  value: any,
): value is Pending$<unknown>;
export function Pending$InFlightAndBuffered$0<AJCB>(value: Pending$<AJCB>): AJCB;
export function Pending$InFlightAndBuffered$operation<AJCB>(
  value: Pending$<AJCB>,
): AJCB;
export function Pending$InFlightAndBuffered$1<AJCB>(value: Pending$<AJCB>): AJCB;
export function Pending$InFlightAndBuffered$buffered<AJCB>(
  value: Pending$<AJCB>,
): AJCB;

export type Pending$<AJCB> = Idle | InFlight<AJCB> | InFlightAndBuffered<AJCB>;

export function to_head_context<AJCC, AJCG>(
  log: _.List<LogEntry$<AJCC>>,
  reference_sequence_number: number,
  sequence_number: number,
  operation: AJCC,
  transform_against: (x0: AJCC, x1: LogEntry$<AJCC>) => _.Result<AJCC, AJCG>
): _.Result<AJCC, AJCG>;

export function in_flight<AJCL>(pending: Pending$<AJCL>): _.Result<
  AJCL,
  undefined
>;

export function buffered<AJCP>(pending: Pending$<AJCP>): _.Result<
  AJCP,
  undefined
>;

export function hold_local<AJCT, AJCV>(
  pending: Pending$<AJCT>,
  edit: AJCT,
  compose: (x0: AJCT, x1: AJCT) => _.Result<AJCT, AJCV>
): _.Result<[Pending$<AJCT>, $option.Option$<AJCT>], AJCV>;

export function rebase_pending<AJDC, AJDE>(
  pending: Pending$<AJDC>,
  remote: AJDC,
  rebase_local: (x0: AJDC, x1: AJDC) => _.Result<AJDC, AJDE>,
  advance_remote: (x0: AJDC, x1: AJDC) => _.Result<AJDC, AJDE>
): _.Result<[Pending$<AJDC>, AJDC], AJDE>;

export function gc_log<AJDM>(
  log: _.List<LogEntry$<AJDM>>,
  minimum_sequence_number: number
): _.List<LogEntry$<AJDM>>;

export function promote_buffer<AJDR, AJDT>(
  pending: Pending$<AJDR>,
  sequence_number: number,
  make_wire: (x0: number, x1: AJDR) => AJDT
): [Pending$<AJDR>, $option.Option$<AJDT>];

export function take_pending<AJDW>(pending: $option.Option$<AJDW>): [
  $option.Option$<AJDW>,
  $option.Option$<AJDW>
];
