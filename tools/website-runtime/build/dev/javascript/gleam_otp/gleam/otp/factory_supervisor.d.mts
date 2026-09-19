import type * as $atom from "../../../gleam_erlang/gleam/erlang/atom.d.mts";
import type * as $process from "../../../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $actor from "../../gleam/otp/actor.d.mts";
import type * as $result2 from "../../gleam/otp/internal/result2.d.mts";
import type * as $supervision from "../../gleam/otp/supervision.d.mts";

declare class Supervisor extends _.CustomType {
  /** @deprecated */
  constructor(handle: SupervisorHandle$);
  /** @deprecated */
  handle: SupervisorHandle$;
}

export type Supervisor$<ESN, ESO> = Supervisor;

type SupervisorHandle$ = any;

export type Message$<ESP, ESQ> = any;

declare class Builder<ESR, ESS> extends _.CustomType {
  /** @deprecated */
  constructor(
    child_type: $supervision.ChildType$,
    template: (x0: ESR) => _.Result<$actor.Started$<ESS>, $actor.StartError$>,
    restart_strategy: $supervision.Restart$,
    intensity: number,
    period: number,
    name: $option.Option$<$process.Name$<Message$<ESR, ESS>>>
  );
  /** @deprecated */
  child_type: $supervision.ChildType$;
  /** @deprecated */
  template: (x0: ESR) => _.Result<$actor.Started$<ESS>, $actor.StartError$>;
  /** @deprecated */
  restart_strategy: $supervision.Restart$;
  /** @deprecated */
  intensity: number;
  /** @deprecated */
  period: number;
  /** @deprecated */
  name: $option.Option$<$process.Name$<Message$<ESR, ESS>>>;
}

export type Builder$<ESR, ESS> = Builder<ESR, ESS>;

type ErlangStartFlags$ = any;

declare class Local<EST, ESU> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $process.Name$<Message$<EST, ESU>>);
  /** @deprecated */
  0: $process.Name$<Message$<EST, ESU>>;
}

type ErlangSupervisorName$<EST, ESU> = Local<EST, ESU>;

declare class SimpleOneForOne extends _.CustomType {}

type Strategy$ = SimpleOneForOne;

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

type ErlangStartFlag$<ESV> = Strategy | Intensity | Period;

type ErlangChildSpec$ = any;

declare class Id extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: number);
  /** @deprecated */
  0: number;
}

declare class Start<ESW, ESX> extends _.CustomType {
  /** @deprecated */
  constructor(
    argument$0: [
      $atom.Atom$,
      $atom.Atom$,
      _.List<(x0: ESW) => _.Result<$actor.Started$<ESX>, $actor.StartError$>>
    ]
  );
  /** @deprecated */
  0: [
    $atom.Atom$,
    $atom.Atom$,
    _.List<(x0: ESW) => _.Result<$actor.Started$<ESX>, $actor.StartError$>>
  ];
}

declare class Restart extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $supervision.Restart$);
  /** @deprecated */
  0: $supervision.Restart$;
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

type ErlangChildSpecProperty$<ESW, ESX> = Id | Start<ESW, ESX> | Restart | Type | Shutdown;

type Timeout$ = any;

export function get_by_name<ETD, ETE>(name: $process.Name$<Message$<ETD, ETE>>): Supervisor$<
  ETD,
  ETE
>;

export function worker_child<ETK, ETL>(
  template: (x0: ETK) => _.Result<$actor.Started$<ETL>, $actor.StartError$>
): Builder$<ETK, ETL>;

export function supervisor_child<ETP, ETQ>(
  template: (x0: ETP) => _.Result<$actor.Started$<ETQ>, $actor.StartError$>
): Builder$<ETP, ETQ>;

export function named<ETU, ETV>(
  builder: Builder$<ETU, ETV>,
  name: $process.Name$<Message$<ETU, ETV>>
): Builder$<ETU, ETV>;

export function restart_tolerance<EUD, EUE>(
  builder: Builder$<EUD, EUE>,
  intensity: number,
  period: number
): Builder$<EUD, EUE>;

export function timeout<EUJ, EUK>(builder: Builder$<EUJ, EUK>, ms: number): Builder$<
  EUJ,
  EUK
>;

export function restart_strategy<EUP, EUQ>(
  builder: Builder$<EUP, EUQ>,
  restart_strategy: $supervision.Restart$
): Builder$<EUP, EUQ>;

export function start<EUV, EUW>(builder: Builder$<EUV, EUW>): _.Result<
  $actor.Started$<Supervisor$<EUV, EUW>>,
  $actor.StartError$
>;

export function supervised<EVU, EVV>(builder: Builder$<EVU, EVV>): $supervision.ChildSpecification$<
  Supervisor$<EVU, EVV>
>;

export function start_child<EWB, EWC>(
  supervisor: Supervisor$<EWB, EWC>,
  argument: EWB
): _.Result<$actor.Started$<EWC>, $actor.StartError$>;

export function count_children(factory: Supervisor$<any, any>): number;

export function init(start_data: $dynamic.Dynamic$): _.Result<
  $dynamic.Dynamic$,
  any
>;

export function start_child_callback<EWU, EWV>(
  start: (x0: EWU) => _.Result<$actor.Started$<EWV>, $actor.StartError$>,
  argument: EWU
): $result2.Result2$<$process.Pid$, EWV, $actor.StartError$>;
