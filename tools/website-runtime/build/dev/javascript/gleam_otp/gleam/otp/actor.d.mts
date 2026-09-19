import type * as $charlist from "../../../gleam_erlang/gleam/erlang/charlist.d.mts";
import type * as $process from "../../../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $dynamic from "../../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $option from "../../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $system from "../../gleam/otp/system.d.mts";

declare class Message<DWU> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: DWU);
  /** @deprecated */
  0: DWU;
}

declare class System extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $system.SystemMessage$);
  /** @deprecated */
  0: $system.SystemMessage$;
}

declare class Unexpected extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $dynamic.Dynamic$);
  /** @deprecated */
  0: $dynamic.Dynamic$;
}

type Message$<DWU> = Message<DWU> | System | Unexpected;

declare class Continue<DWV, DWW> extends _.CustomType {
  /** @deprecated */
  constructor(state: DWV, selector: $option.Option$<$process.Selector$<DWW>>);
  /** @deprecated */
  state: DWV;
  /** @deprecated */
  selector: $option.Option$<$process.Selector$<DWW>>;
}

declare class Stop extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $process.ExitReason$);
  /** @deprecated */
  0: $process.ExitReason$;
}

export type Next$<DWV, DWW> = Continue<DWV, DWW> | Stop;

declare class Self<DWX, DWY> extends _.CustomType {
  /** @deprecated */
  constructor(
    mode: $system.Mode$,
    parent: $process.Pid$,
    state: DWX,
    selector: $process.Selector$<Message$<DWY>>,
    debug_state: $system.DebugState$,
    message_handler: (x0: DWX, x1: DWY) => Next$<DWX, DWY>
  );
  /** @deprecated */
  mode: $system.Mode$;
  /** @deprecated */
  parent: $process.Pid$;
  /** @deprecated */
  state: DWX;
  /** @deprecated */
  selector: $process.Selector$<Message$<DWY>>;
  /** @deprecated */
  debug_state: $system.DebugState$;
  /** @deprecated */
  message_handler: (x0: DWX, x1: DWY) => Next$<DWX, DWY>;
}

type Self$<DWX, DWY> = Self<DWX, DWY>;

export class Started<DWZ> extends _.CustomType {
  /** @deprecated */
  constructor(pid: $process.Pid$, data: DWZ);
  /** @deprecated */
  pid: $process.Pid$;
  /** @deprecated */
  data: DWZ;
}
export function Started$Started<DWZ>(
  pid: $process.Pid$,
  data: DWZ,
): Started$<DWZ>;
export function Started$isStarted<DWZ>(value: any): value is Started$<unknown>;
export function Started$Started$0<DWZ>(value: Started$<DWZ>): $process.Pid$;
export function Started$Started$pid<DWZ>(value: Started$<DWZ>): $process.Pid$;
export function Started$Started$1<DWZ>(value: Started$<DWZ>): DWZ;
export function Started$Started$data<DWZ>(value: Started$<DWZ>): DWZ;

export type Started$<DWZ> = Started<DWZ>;

declare class Initialised<DXA, DXB, DXC> extends _.CustomType {
  /** @deprecated */
  constructor(
    state: DXA,
    selector: $option.Option$<$process.Selector$<DXB>>,
    return$: DXC
  );
  /** @deprecated */
  state: DXA;
  /** @deprecated */
  selector: $option.Option$<$process.Selector$<DXB>>;
  /** @deprecated */
  return: DXC;
}

export type Initialised$<DXA, DXB, DXC> = Initialised<DXA, DXB, DXC>;

declare class Builder<DXD, DXE, DXF> extends _.CustomType {
  /** @deprecated */
  constructor(
    initialise: (x0: $process.Subject$<DXE>) => _.Result<
      Initialised$<DXD, DXE, DXF>,
      string
    >,
    initialisation_timeout: number,
    on_message: (x0: DXD, x1: DXE) => Next$<DXD, DXE>,
    name: $option.Option$<$process.Name$<DXE>>
  );
  /** @deprecated */
  initialise: (x0: $process.Subject$<DXE>) => _.Result<
    Initialised$<DXD, DXE, DXF>,
    string
  >;
  /** @deprecated */
  initialisation_timeout: number;
  /** @deprecated */
  on_message: (x0: DXD, x1: DXE) => Next$<DXD, DXE>;
  /** @deprecated */
  name: $option.Option$<$process.Name$<DXE>>;
}

export type Builder$<DXD, DXE, DXF> = Builder<DXD, DXE, DXF>;

export class InitTimeout extends _.CustomType {}
export function StartError$InitTimeout(): StartError$;
export function StartError$isInitTimeout(value: any): value is StartError$;

export class InitFailed extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: string);
  /** @deprecated */
  0: string;
}
export function StartError$InitFailed($0: string): StartError$;
export function StartError$isInitFailed(value: any): value is StartError$;
export function StartError$InitFailed$0(value: StartError$): string;

export class InitExited extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $process.ExitReason$);
  /** @deprecated */
  0: $process.ExitReason$;
}
export function StartError$InitExited($0: $process.ExitReason$): StartError$;
export function StartError$isInitExited(value: any): value is StartError$;
export function StartError$InitExited$0(value: StartError$): $process.ExitReason$;

export type StartError$ = InitTimeout | InitFailed | InitExited;

declare class Ack<DXG> extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: _.Result<DXG, string>);
  /** @deprecated */
  0: _.Result<DXG, string>;
}

declare class Mon extends _.CustomType {
  /** @deprecated */
  constructor(argument$0: $process.Down$);
  /** @deprecated */
  0: $process.Down$;
}

type StartInitMessage$<DXG> = Ack<DXG> | Mon;

export type StartResult = _.Result<Started$<any>, StartError$>;

export function continue$<DXL>(state: DXL): Next$<DXL, any>;

export function stop(): Next$<any, any>;

export function stop_abnormal(reason: string): Next$<any, any>;

export function with_selector<DXX, DXY>(
  value: Next$<DXX, DXY>,
  selector: $process.Selector$<DXY>
): Next$<DXX, DXY>;

export function initialised<DYE>(state: DYE): Initialised$<DYE, any, undefined>;

export function selecting<DYJ, DYL, DYP>(
  initialised: Initialised$<DYJ, any, DYL>,
  selector: $process.Selector$<DYP>
): Initialised$<DYJ, DYP, DYL>;

export function returning<DYU, DYV, DZA>(
  initialised: Initialised$<DYU, DYV, any>,
  return$: DZA
): Initialised$<DYU, DYV, DZA>;

export function new$<DZE, DZF>(state: DZE): Builder$<
  DZE,
  DZF,
  $process.Subject$<DZF>
>;

export function new_with_initialiser<DZK, DZM, DZN>(
  timeout: number,
  initialise: (x0: $process.Subject$<DZK>) => _.Result<
    Initialised$<DZM, DZK, DZN>,
    string
  >
): Builder$<DZM, DZK, DZN>;

export function on_message<DZW, DZX, DZY>(
  builder: Builder$<DZW, DZX, DZY>,
  handler: (x0: DZW, x1: DZX) => Next$<DZW, DZX>
): Builder$<DZW, DZX, DZY>;

export function named<EAH, EAI, EAJ>(
  builder: Builder$<EAH, EAI, EAJ>,
  name: $process.Name$<EAI>
): Builder$<EAH, EAI, EAJ>;

export function start<ECC>(builder: Builder$<any, any, ECC>): _.Result<
  Started$<ECC>,
  StartError$
>;

export function send<ECJ>(subject: $process.Subject$<ECJ>, msg: ECJ): undefined;

export function call<ECL, ECN>(
  subject: $process.Subject$<ECL>,
  timeout: number,
  make_message: (x0: $process.Subject$<ECN>) => ECL
): ECN;
