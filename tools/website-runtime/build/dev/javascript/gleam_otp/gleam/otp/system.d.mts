import type * as $atom from "../../../gleam_erlang/gleam/erlang/atom.d.mts";
import type * as $process from "../../../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "../../gleam.d.mts";

export class Running extends _.CustomType {}
export function Mode$Running(): Mode$;
export function Mode$isRunning(value: any): value is Mode$;

export class Suspended extends _.CustomType {}
export function Mode$Suspended(): Mode$;
export function Mode$isSuspended(value: any): value is Mode$;

export type Mode$ = Running | Suspended;

export class NoDebug extends _.CustomType {}
export function DebugOption$NoDebug(): DebugOption$;
export function DebugOption$isNoDebug(value: any): value is DebugOption$;

export type DebugOption$ = NoDebug;

export type DebugState$ = any;

export class StatusInfo extends _.CustomType {
  /** @deprecated */
  constructor(
    module: $atom.Atom$,
    parent: $process.Pid$,
    mode: Mode$,
    debug_state: DebugState$,
    state: $dynamic.Dynamic$
  );
  /** @deprecated */
  module: $atom.Atom$;
  /** @deprecated */
  parent: $process.Pid$;
  /** @deprecated */
  mode: Mode$;
  /** @deprecated */
  debug_state: DebugState$;
  /** @deprecated */
  state: $dynamic.Dynamic$;
}
export function StatusInfo$StatusInfo(
  module: $atom.Atom$,
  parent: $process.Pid$,
  mode: Mode$,
  debug_state: DebugState$,
  state: $dynamic.Dynamic$,
): StatusInfo$;
export function StatusInfo$isStatusInfo(value: any): value is StatusInfo$;
export function StatusInfo$StatusInfo$0(value: StatusInfo$): $atom.Atom$;
export function StatusInfo$StatusInfo$module(value: StatusInfo$): $atom.Atom$;
export function StatusInfo$StatusInfo$1(value: StatusInfo$): $process.Pid$;
export function StatusInfo$StatusInfo$parent(value: StatusInfo$): $process.Pid$;
export function StatusInfo$StatusInfo$2(value: StatusInfo$): Mode$;
export function StatusInfo$StatusInfo$mode(value: StatusInfo$): Mode$;
export function StatusInfo$StatusInfo$3(value: StatusInfo$): DebugState$;
export function StatusInfo$StatusInfo$debug_state(value: StatusInfo$): DebugState$;
export function StatusInfo$StatusInfo$4(
  value: StatusInfo$,
): $dynamic.Dynamic$;
export function StatusInfo$StatusInfo$state(value: StatusInfo$): $dynamic.Dynamic$;

export type StatusInfo$ = StatusInfo;

export class Resume extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: () => undefined);
  /** @deprecated */
  0: () => undefined;
}
export function SystemMessage$Resume($0: () => undefined): SystemMessage$;
export function SystemMessage$isResume(value: any): value is SystemMessage$;
export function SystemMessage$Resume$0(value: SystemMessage$): () => undefined;

export class Suspend extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: () => undefined);
  /** @deprecated */
  0: () => undefined;
}
export function SystemMessage$Suspend($0: () => undefined): SystemMessage$;
export function SystemMessage$isSuspend(value: any): value is SystemMessage$;
export function SystemMessage$Suspend$0(value: SystemMessage$): () => undefined;

export class GetState extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: (x0: $dynamic.Dynamic$) => undefined);
  /** @deprecated */
  0: (x0: $dynamic.Dynamic$) => undefined;
}
export function SystemMessage$GetState(
  $0: (x0: $dynamic.Dynamic$) => undefined,
): SystemMessage$;
export function SystemMessage$isGetState(value: any): value is SystemMessage$;
export function SystemMessage$GetState$0(value: SystemMessage$): (
  x0: $dynamic.Dynamic$
) => undefined;

export class GetStatus extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: (x0: StatusInfo$) => undefined);
  /** @deprecated */
  0: (x0: StatusInfo$) => undefined;
}
export function SystemMessage$GetStatus(
  $0: (x0: StatusInfo$) => undefined,
): SystemMessage$;
export function SystemMessage$isGetStatus(value: any): value is SystemMessage$;
export function SystemMessage$GetStatus$0(value: SystemMessage$): (
  x0: StatusInfo$
) => undefined;

export type SystemMessage$ = Resume | Suspend | GetState | GetStatus;

type DoNotLeak$ = any;

export function debug_state(a: _.List<DebugOption$>): DebugState$;

export function get_state(from: $process.Pid$): $dynamic.Dynamic$;

export function suspend(pid: $process.Pid$): undefined;

export function resume(pid: $process.Pid$): undefined;
