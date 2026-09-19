import type * as $process from "../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $actor from "../gleam_otp/gleam/otp/actor.d.mts";
import type * as $factory_supervisor from "../gleam_otp/gleam/otp/factory_supervisor.d.mts";
import type * as $supervision from "../gleam_otp/gleam/otp/supervision.d.mts";
import type * as _ from "./gleam.d.mts";
import type * as $effect from "./lustre/effect.d.mts";
import type * as $app from "./lustre/runtime/app.d.mts";
import type * as $runtime from "./lustre/runtime/server/runtime.d.mts";
import type * as $vnode from "./lustre/vdom/vnode.d.mts";

export class ActorError extends _.CustomType {
  /** @deprecated */
  constructor(reason: $actor.StartError$);
  /** @deprecated */
  reason: $actor.StartError$;
}
export function Error$ActorError(reason: $actor.StartError$): Error$;
export function Error$isActorError(value: any): value is Error$;
export function Error$ActorError$0(value: Error$): $actor.StartError$;
export function Error$ActorError$reason(value: Error$): $actor.StartError$;

export class BadComponentName extends _.CustomType {
  /** @deprecated */
  constructor(name: string);
  /** @deprecated */
  name: string;
}
export function Error$BadComponentName(name: string): Error$;
export function Error$isBadComponentName(value: any): value is Error$;
export function Error$BadComponentName$0(value: Error$): string;
export function Error$BadComponentName$name(value: Error$): string;

export class ComponentAlreadyRegistered extends _.CustomType {
  /** @deprecated */
  constructor(name: string);
  /** @deprecated */
  name: string;
}
export function Error$ComponentAlreadyRegistered(name: string): Error$;
export function Error$isComponentAlreadyRegistered(value: any): value is Error$;
export function Error$ComponentAlreadyRegistered$0(value: Error$): string;
export function Error$ComponentAlreadyRegistered$name(value: Error$): string;

export class ElementNotFound extends _.CustomType {
  /** @deprecated */
  constructor(selector: string);
  /** @deprecated */
  selector: string;
}
export function Error$ElementNotFound(selector: string): Error$;
export function Error$isElementNotFound(value: any): value is Error$;
export function Error$ElementNotFound$0(value: Error$): string;
export function Error$ElementNotFound$selector(value: Error$): string;

export class NotABrowser extends _.CustomType {}
export function Error$NotABrowser(): Error$;
export function Error$isNotABrowser(value: any): value is Error$;

export type Error$ = ActorError | BadComponentName | ComponentAlreadyRegistered | ElementNotFound | NotABrowser;

export type Runtime$<YED> = any;

export type App = $app.App$<any, any, any>;

export type RuntimeMessage = $runtime.Message$<any>;

export function application<YEZ, YFA, YFB>(
  init: (x0: YEZ) => [YFA, $effect.Effect$<YFB>],
  update: (x0: YFA, x1: YFB) => [YFA, $effect.Effect$<YFB>],
  view: (x0: YFA) => $vnode.Element$<YFB>
): $app.App$<YEZ, YFA, YFB>;

export function element<YEM>(view: $vnode.Element$<YEM>): $app.App$<
  any,
  undefined,
  YEM
>;

export function simple<YES, YET, YEU>(
  init: (x0: YES) => YET,
  update: (x0: YET, x1: YEU) => YET,
  view: (x0: YET) => $vnode.Element$<YEU>
): $app.App$<YES, YET, YEU>;

export function component<YFI, YFJ, YFK>(
  init: (x0: YFI) => [YFJ, $effect.Effect$<YFK>],
  update: (x0: YFJ, x1: YFK) => [YFJ, $effect.Effect$<YFK>],
  view: (x0: YFJ) => $vnode.Element$<YFK>,
  options: _.List<$app.Option$<YFK>>
): $app.App$<YFI, YFJ, YFK>;

export function named<YFT, YFU, YFV>(
  app: $app.App$<YFT, YFU, YFV>,
  name: $process.Name$<$runtime.Message$<YFV>>
): $app.App$<YFT, YFU, YFV>;

export function is_browser(): boolean;

export function start<YGE, YGG>(
  app: $app.App$<YGE, any, YGG>,
  selector: string,
  arguments$: YGE
): _.Result<Runtime$<YGG>, Error$>;

export function start_server_component<YGW, YGY>(
  app: $app.App$<YGW, any, YGY>,
  arguments$: YGW
): _.Result<Runtime$<YGY>, Error$>;

export function supervised<YHF, YHH>(
  app: $app.App$<YHF, any, YHH>,
  arguments$: YHF
): $supervision.ChildSpecification$<$process.Subject$<$runtime.Message$<YHH>>>;

export function factory<YHO, YHQ>(app: $app.App$<YHO, any, YHQ>): $factory_supervisor.Builder$<
  YHO,
  $process.Subject$<$runtime.Message$<YHQ>>
>;

export function register(x0: $app.App$<undefined, any, any>, x1: string): _.Result<
  undefined,
  Error$
>;

export function send<YIF>(
  runtime: Runtime$<YIF>,
  message: $runtime.Message$<YIF>
): undefined;

export function dispatch<YII>(message: YII): $runtime.Message$<YII>;

export function shutdown(): $runtime.Message$<any>;

export function is_registered(x0: string): boolean;
