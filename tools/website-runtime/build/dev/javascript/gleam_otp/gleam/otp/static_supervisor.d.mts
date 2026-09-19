import type * as $atom from "../../../gleam_erlang/gleam/erlang/atom.d.mts";
import type * as $process from "../../../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $actor from "../../gleam/otp/actor.d.mts";
import type * as $supervision from "../../gleam/otp/supervision.d.mts";

declare class Supervisor extends _.CustomType {
  /** @deprecated */
  constructor(pid: $process.Pid$);
  /** @deprecated */
  pid: $process.Pid$;
}

export type Supervisor$ = Supervisor;

export class OneForOne extends _.CustomType {}
export function Strategy$OneForOne(): Strategy$;
export function Strategy$isOneForOne(value: any): value is Strategy$;

export class OneForAll extends _.CustomType {}
export function Strategy$OneForAll(): Strategy$;
export function Strategy$isOneForAll(value: any): value is Strategy$;

export class RestForOne extends _.CustomType {}
export function Strategy$RestForOne(): Strategy$;
export function Strategy$isRestForOne(value: any): value is Strategy$;

export type Strategy$ = OneForOne | OneForAll | RestForOne;

export class Never extends _.CustomType {}
export function AutoShutdown$Never(): AutoShutdown$;
export function AutoShutdown$isNever(value: any): value is AutoShutdown$;

export class AnySignificant extends _.CustomType {}
export function AutoShutdown$AnySignificant(): AutoShutdown$;
export function AutoShutdown$isAnySignificant(
  value: any,
): value is AutoShutdown$;

export class AllSignificant extends _.CustomType {}
export function AutoShutdown$AllSignificant(): AutoShutdown$;
export function AutoShutdown$isAllSignificant(
  value: any,
): value is AutoShutdown$;

export type AutoShutdown$ = Never | AnySignificant | AllSignificant;

declare class Builder extends _.CustomType {
  /** @deprecated */
  constructor(
    strategy: Strategy$,
    intensity: number,
    period: number,
    auto_shutdown: AutoShutdown$,
    children: _.List<$supervision.ChildSpecification$<undefined>>
  );
  /** @deprecated */
  strategy: Strategy$;
  /** @deprecated */
  intensity: number;
  /** @deprecated */
  period: number;
  /** @deprecated */
  auto_shutdown: AutoShutdown$;
  /** @deprecated */
  children: _.List<$supervision.ChildSpecification$<undefined>>;
}

export type Builder$ = Builder;

type ErlangStartFlags$ = any;

declare class Strategy extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: Strategy$);
  /** @deprecated */
  0: Strategy$;
}

declare class Intensity extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}

declare class Period extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}

declare class AutoShutdown extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: AutoShutdown$);
  /** @deprecated */
  0: AutoShutdown$;
}

type ErlangStartFlag$<FDY> = Strategy | Intensity | Period | AutoShutdown;

type ErlangChildSpec$ = any;

declare class Id extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}

declare class Start<FDZ> extends _.CustomType {
  /** @deprecated */
  constructor(
    argument$0: [
      $atom.Atom$,
      $atom.Atom$,
      _.List<() => _.Result<$actor.Started$<FDZ>, $actor.StartError$>>
    ]
  );
  /** @deprecated */
  0: [
    $atom.Atom$,
    $atom.Atom$,
    _.List<() => _.Result<$actor.Started$<FDZ>, $actor.StartError$>>
  ];
}

declare class Restart extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $supervision.Restart$);
  /** @deprecated */
  0: $supervision.Restart$;
}

declare class Significant extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: boolean);
  /** @deprecated */
  0: boolean;
}

declare class Type extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $atom.Atom$);
  /** @deprecated */
  0: $atom.Atom$;
}

declare class Shutdown extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: Timeout$);
  /** @deprecated */
  0: Timeout$;
}

type ErlangChildSpecProperty$<FDZ> = Id | Start<FDZ> | Restart | Significant | Type | Shutdown;

type Timeout$ = any;

export function new$(strategy: Strategy$): Builder$;

export function restart_tolerance(
  builder: Builder$,
  intensity: number,
  period: number
): Builder$;

export function auto_shutdown(builder: Builder$, value: AutoShutdown$): Builder$;

export function start(builder: Builder$): _.Result<
  $actor.Started$<Supervisor$>,
  $actor.StartError$
>;

export function supervised(builder: Builder$): $supervision.ChildSpecification$<
  Supervisor$
>;

export function add(
  builder: Builder$,
  child: $supervision.ChildSpecification$<any>
): Builder$;

export function init(start_data: $dynamic.Dynamic$): _.Result<
  $dynamic.Dynamic$,
  any
>;

export function start_child_callback(
  start: () => _.Result<$actor.Started$<any>, $actor.StartError$>
): _.Result<$process.Pid$, $actor.StartError$>;
