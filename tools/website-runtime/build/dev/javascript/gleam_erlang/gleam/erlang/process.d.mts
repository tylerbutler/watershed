import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $port from "../../gleam/erlang/port.d.mts";
import type * as $reference from "../../gleam/erlang/reference.d.mts";

export type Pid$ = any;

declare class Subject extends _.CustomType {
  /** @deprecated */
  constructor(owner: Pid$, tag: $dynamic.Dynamic$);
  /** @deprecated */
  owner: Pid$;
  /** @deprecated */
  tag: $dynamic.Dynamic$;
}

declare class NamedSubject<DKM> extends _.CustomType {
  /** @deprecated */
  constructor(name: Name$<DKM>);
  /** @deprecated */
  name: Name$<DKM>;
}

export type Subject$<DKM> = Subject | NamedSubject<DKM>;

export type Name$<DKN> = any;

type DoNotLeak$ = any;

export type Selector$<DKO> = any;

export class ExitMessage extends _.CustomType {
  /** @deprecated */
  constructor(pid: Pid$, reason: ExitReason$);
  /** @deprecated */
  pid: Pid$;
  /** @deprecated */
  reason: ExitReason$;
}
export function ExitMessage$ExitMessage(
  pid: Pid$,
  reason: ExitReason$,
): ExitMessage$;
export function ExitMessage$isExitMessage(value: any): value is ExitMessage$;
export function ExitMessage$ExitMessage$0(value: ExitMessage$): Pid$;
export function ExitMessage$ExitMessage$pid(value: ExitMessage$): Pid$;
export function ExitMessage$ExitMessage$1(value: ExitMessage$): ExitReason$;
export function ExitMessage$ExitMessage$reason(value: ExitMessage$): ExitReason$;

export type ExitMessage$ = ExitMessage;

export class Normal extends _.CustomType {}
export function ExitReason$Normal(): ExitReason$;
export function ExitReason$isNormal(value: any): value is ExitReason$;

export class Killed extends _.CustomType {}
export function ExitReason$Killed(): ExitReason$;
export function ExitReason$isKilled(value: any): value is ExitReason$;

export class Abnormal extends _.CustomType {
  /** @deprecated */
  constructor(reason: $dynamic.Dynamic$);
  /** @deprecated */
  reason: $dynamic.Dynamic$;
}
export function ExitReason$Abnormal(reason: $dynamic.Dynamic$): ExitReason$;
export function ExitReason$isAbnormal(value: any): value is ExitReason$;
export function ExitReason$Abnormal$0(value: ExitReason$): $dynamic.Dynamic$;
export function ExitReason$Abnormal$reason(value: ExitReason$): $dynamic.Dynamic$;

export type ExitReason$ = Normal | Killed | Abnormal;

declare class Anything extends _.CustomType {}

type AnythingSelectorTag$ = Anything;

declare class Process extends _.CustomType {}

type ProcessMonitorFlag$ = Process;

export type Monitor$ = any;

export class ProcessDown extends _.CustomType {
  /** @deprecated */
  constructor(monitor: Monitor$, pid: Pid$, reason: ExitReason$);
  /** @deprecated */
  monitor: Monitor$;
  /** @deprecated */
  pid: Pid$;
  /** @deprecated */
  reason: ExitReason$;
}
export function Down$ProcessDown(
  monitor: Monitor$,
  pid: Pid$,
  reason: ExitReason$,
): Down$;
export function Down$isProcessDown(value: any): value is Down$;
export function Down$ProcessDown$0(value: Down$): Monitor$;
export function Down$ProcessDown$monitor(value: Down$): Monitor$;
export function Down$ProcessDown$1(value: Down$): Pid$;
export function Down$ProcessDown$pid(value: Down$): Pid$;
export function Down$ProcessDown$2(value: Down$): ExitReason$;
export function Down$ProcessDown$reason(value: Down$): ExitReason$;

export class PortDown extends _.CustomType {
  /** @deprecated */
  constructor(monitor: Monitor$, port: $port.Port$, reason: ExitReason$);
  /** @deprecated */
  monitor: Monitor$;
  /** @deprecated */
  port: $port.Port$;
  /** @deprecated */
  reason: ExitReason$;
}
export function Down$PortDown(
  monitor: Monitor$,
  port: $port.Port$,
  reason: ExitReason$,
): Down$;
export function Down$isPortDown(value: any): value is Down$;
export function Down$PortDown$0(value: Down$): Monitor$;
export function Down$PortDown$monitor(value: Down$): Monitor$;
export function Down$PortDown$1(value: Down$): $port.Port$;
export function Down$PortDown$port(value: Down$): $port.Port$;
export function Down$PortDown$2(value: Down$): ExitReason$;
export function Down$PortDown$reason(value: Down$): ExitReason$;

export type Down$ = ProcessDown | PortDown;

export function Down$monitor(value: Down$): Monitor$;
export function Down$reason(value: Down$): ExitReason$;

export type Timer$ = any;

export class TimerNotFound extends _.CustomType {}
export function Cancelled$TimerNotFound(): Cancelled$;
export function Cancelled$isTimerNotFound(value: any): value is Cancelled$;

export class Cancelled extends _.CustomType {
  /** @deprecated */
  constructor(time_remaining: number);
  /** @deprecated */
  time_remaining: number;
}
export function Cancelled$Cancelled(time_remaining: number): Cancelled$;
export function Cancelled$isCancelled(value: any): value is Cancelled$;
export function Cancelled$Cancelled$0(value: Cancelled$): number;
export function Cancelled$Cancelled$time_remaining(value: Cancelled$): number;

export type Cancelled$ = TimerNotFound | Cancelled;

declare class Kill extends _.CustomType {}

type KillFlag$ = Kill;

export function self(): Pid$;

export function spawn(running: () => any): Pid$;

export function spawn_unlinked(a: () => any): Pid$;

export function unsafely_create_subject(owner: Pid$, tag: $dynamic.Dynamic$): Subject$<
  any
>;

export function new_name(prefix: string): Name$<any>;

export function named_subject<DKV>(name: Name$<DKV>): Subject$<DKV>;

export function subject_name<DKY>(subject: Subject$<DKY>): _.Result<
  Name$<DKY>,
  undefined
>;

export function new_subject(): Subject$<any>;

export function named(name: Name$<any>): _.Result<Pid$, undefined>;

export function subject_owner(subject: Subject$<any>): _.Result<Pid$, undefined>;

export function send<DLK>(subject: Subject$<DLK>, message: DLK): undefined;

export function receive<DLM>(subject: Subject$<DLM>, timeout: number): _.Result<
  DLM,
  undefined
>;

export function receive_forever<DLU>(subject: Subject$<DLU>): DLU;

export function new_selector(): Selector$<any>;

export function selector_receive<DLY>(from: Selector$<DLY>, within: number): _.Result<
  DLY,
  undefined
>;

export function selector_receive_forever<DMC>(from: Selector$<DMC>): DMC;

export function map_selector<DME, DMG>(a: Selector$<DME>, b: (x0: DME) => DMG): Selector$<
  DMG
>;

export function merge_selector<DMI>(a: Selector$<DMI>, b: Selector$<DMI>): Selector$<
  DMI
>;

export function select_trapped_exits<DMM>(
  selector: Selector$<DMM>,
  handler: (x0: ExitMessage$) => DMM
): Selector$<DMM>;

export function flush_messages(): undefined;

export function select_map<DMT, DMV>(
  selector: Selector$<DMT>,
  subject: Subject$<DMV>,
  transform: (x0: DMV) => DMT
): Selector$<DMT>;

export function select<DMP>(selector: Selector$<DMP>, subject: Subject$<DMP>): Selector$<
  DMP
>;

export function deselect<DMY>(selector: Selector$<DMY>, subject: Subject$<any>): Selector$<
  DMY
>;

export function select_record<DND>(
  selector: Selector$<DND>,
  tag: any,
  arity: number,
  transform: (x0: $dynamic.Dynamic$) => DND
): Selector$<DND>;

export function select_other<DNH>(
  selector: Selector$<DNH>,
  handler: (x0: $dynamic.Dynamic$) => DNH
): Selector$<DNH>;

export function sleep(a: number): undefined;

export function sleep_forever(): undefined;

export function is_alive(a: Pid$): boolean;

export function monitor(pid: Pid$): Monitor$;

export function select_specific_monitor<DNT>(
  selector: Selector$<DNT>,
  monitor: Monitor$,
  mapping: (x0: Down$) => DNT
): Selector$<DNT>;

export function select_monitors<DNW>(
  selector: Selector$<DNW>,
  mapping: (x0: Down$) => DNW
): Selector$<DNW>;

export function demonitor_process(monitor: Monitor$): undefined;

export function deselect_specific_monitor<DNZ>(
  selector: Selector$<DNZ>,
  monitor: Monitor$
): Selector$<DNZ>;

export function call<DOJ, DOL>(
  subject: Subject$<DOJ>,
  timeout: number,
  make_request: (x0: Subject$<DOL>) => DOJ
): DOL;

export function call_forever<DON, DOP>(
  subject: Subject$<DON>,
  make_request: (x0: Subject$<DOP>) => DON
): DOP;

export function link(pid: Pid$): boolean;

export function unlink(pid: Pid$): undefined;

export function send_after<DOV>(
  subject: Subject$<DOV>,
  delay: number,
  message: DOV
): Timer$;

export function cancel_timer(timer: Timer$): Cancelled$;

export function kill(pid: Pid$): undefined;

export function send_exit(pid: Pid$): undefined;

export function send_abnormal_exit(pid: Pid$, reason: any): undefined;

export function trap_exits(a: boolean): undefined;

export function register(pid: Pid$, name: Name$<any>): _.Result<
  undefined,
  undefined
>;

export function unregister(name: Name$<any>): _.Result<undefined, undefined>;
