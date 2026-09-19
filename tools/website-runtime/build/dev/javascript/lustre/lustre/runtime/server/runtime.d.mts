import type * as $process from "../../../../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $json from "../../../../gleam_json/gleam/json.d.mts";
import type * as $actor from "../../../../gleam_otp/gleam/otp/actor.d.mts";
import type * as $dict from "../../../../gleam_stdlib/gleam/dict.d.mts";
import type * as $decode from "../../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../../../gleam_stdlib/gleam/option.d.mts";
import type * as $set from "../../../../gleam_stdlib/gleam/set.d.mts";
import type * as _ from "../../../gleam.d.mts";
import type * as $effect from "../../../lustre/effect.d.mts";
import type * as $transport from "../../../lustre/runtime/transport.d.mts";
import type * as $cache from "../../../lustre/vdom/cache.d.mts";
import type * as $vnode from "../../../lustre/vdom/vnode.d.mts";

export class State<XJS, XJT> extends _.CustomType {
  /** @deprecated */
  constructor(
    self: $process.Subject$<Message$<XJT>>,
    selector: $process.Selector$<Message$<XJT>>,
    base_selector: $process.Selector$<Message$<XJT>>,
    model: XJS,
    update: (x0: XJS, x1: XJT) => [XJS, $effect.Effect$<XJT>],
    view: (x0: XJS) => $vnode.Element$<XJT>,
    config: Config$<XJT>,
    vdom: $vnode.Element$<XJT>,
    cache: $cache.Cache$<XJT>,
    providers: $dict.Dict$<string, $json.Json$>,
    subscribers: $dict.Dict$<
      $process.Subject$<$transport.ClientMessage$<XJT>>,
      $process.Monitor$
    >,
    callbacks: $set.Set$<(x0: $transport.ClientMessage$<XJT>) => undefined>
  );
  /** @deprecated */
  self: $process.Subject$<Message$<XJT>>;
  /** @deprecated */
  selector: $process.Selector$<Message$<XJT>>;
  /** @deprecated */
  base_selector: $process.Selector$<Message$<XJT>>;
  /** @deprecated */
  model: XJS;
  /** @deprecated */
  update: (x0: XJS, x1: XJT) => [XJS, $effect.Effect$<XJT>];
  /** @deprecated */
  view: (x0: XJS) => $vnode.Element$<XJT>;
  /** @deprecated */
  config: Config$<XJT>;
  /** @deprecated */
  vdom: $vnode.Element$<XJT>;
  /** @deprecated */
  cache: $cache.Cache$<XJT>;
  /** @deprecated */
  providers: $dict.Dict$<string, $json.Json$>;
  /** @deprecated */
  subscribers: $dict.Dict$<
    $process.Subject$<$transport.ClientMessage$<XJT>>,
    $process.Monitor$
  >;
  /** @deprecated */
  callbacks: $set.Set$<(x0: $transport.ClientMessage$<XJT>) => undefined>;
}
export function State$State<XJS, XJT>(
  self: $process.Subject$<Message$<XJT>>,
  selector: $process.Selector$<Message$<XJT>>,
  base_selector: $process.Selector$<Message$<XJT>>,
  model: XJS,
  update: (x0: XJS, x1: XJT) => [XJS, $effect.Effect$<XJT>],
  view: (x0: XJS) => $vnode.Element$<XJT>,
  config: Config$<XJT>,
  vdom: $vnode.Element$<XJT>,
  cache: $cache.Cache$<XJT>,
  providers: $dict.Dict$<string, $json.Json$>,
  subscribers: $dict.Dict$<
    $process.Subject$<$transport.ClientMessage$<XJT>>,
    $process.Monitor$
  >,
  callbacks: $set.Set$<(x0: $transport.ClientMessage$<XJT>) => undefined>,
): State$<XJS, XJT>;
export function State$isState<XJS, XJT>(
  value: any,
): value is State$<unknown, unknown>;
export function State$State$0<XJS, XJT>(value: State$<XJS, XJT>): $process.Subject$<
  Message$<XJT>
>;
export function State$State$self<XJS, XJT>(value: State$<XJS, XJT>): $process.Subject$<
  Message$<XJT>
>;
export function State$State$1<XJS, XJT>(value: State$<XJS, XJT>): $process.Selector$<
  Message$<XJT>
>;
export function State$State$selector<XJS, XJT>(value: State$<XJS, XJT>): $process.Selector$<
  Message$<XJT>
>;
export function State$State$2<XJS, XJT>(value: State$<XJS, XJT>): $process.Selector$<
  Message$<XJT>
>;
export function State$State$base_selector<XJS, XJT>(value: State$<XJS, XJT>): $process.Selector$<
  Message$<XJT>
>;
export function State$State$3<XJS, XJT>(value: State$<XJS, XJT>): XJS;
export function State$State$model<XJS, XJT>(value: State$<XJS, XJT>): XJS;
export function State$State$4<XJS, XJT>(value: State$<XJS, XJT>): (
  x0: XJS,
  x1: XJT
) => [XJS, $effect.Effect$<XJT>];
export function State$State$update<XJS, XJT>(value: State$<XJS, XJT>): (
  x0: XJS,
  x1: XJT
) => [XJS, $effect.Effect$<XJT>];
export function State$State$5<XJS, XJT>(value: State$<XJS, XJT>): (x0: XJS) => $vnode.Element$<
  XJT
>;
export function State$State$view<XJS, XJT>(value: State$<XJS, XJT>): (x0: XJS) => $vnode.Element$<
  XJT
>;
export function State$State$6<XJS, XJT>(value: State$<XJS, XJT>): Config$<XJT>;
export function State$State$config<XJS, XJT>(value: State$<XJS, XJT>): Config$<
  XJT
>;
export function State$State$7<XJS, XJT>(value: State$<XJS, XJT>): $vnode.Element$<
  XJT
>;
export function State$State$vdom<XJS, XJT>(value: State$<XJS, XJT>): $vnode.Element$<
  XJT
>;
export function State$State$8<XJS, XJT>(value: State$<XJS, XJT>): $cache.Cache$<
  XJT
>;
export function State$State$cache<XJS, XJT>(value: State$<XJS, XJT>): $cache.Cache$<
  XJT
>;
export function State$State$9<XJS, XJT>(value: State$<XJS, XJT>): $dict.Dict$<
  string,
  $json.Json$
>;
export function State$State$providers<XJS, XJT>(value: State$<XJS, XJT>): $dict.Dict$<
  string,
  $json.Json$
>;
export function State$State$10<XJS, XJT>(value: State$<XJS, XJT>): $dict.Dict$<
  $process.Subject$<$transport.ClientMessage$<XJT>>,
  $process.Monitor$
>;
export function State$State$subscribers<XJS, XJT>(value: State$<XJS, XJT>): $dict.Dict$<
  $process.Subject$<$transport.ClientMessage$<XJT>>,
  $process.Monitor$
>;
export function State$State$11<XJS, XJT>(value: State$<XJS, XJT>): $set.Set$<
  (x0: $transport.ClientMessage$<XJT>) => undefined
>;
export function State$State$callbacks<XJS, XJT>(value: State$<XJS, XJT>): $set.Set$<
  (x0: $transport.ClientMessage$<XJT>) => undefined
>;

export type State$<XJS, XJT> = State<XJS, XJT>;

export class Config<XJU> extends _.CustomType {
  /** @deprecated */
  constructor(
    open_shadow_root: boolean,
    adopt_styles: boolean,
    attributes: $dict.Dict$<string, (x0: string) => _.Result<XJU, undefined>>,
    properties: $dict.Dict$<string, $decode.Decoder$<XJU>>,
    contexts: $dict.Dict$<string, $decode.Decoder$<XJU>>,
    on_connect: $option.Option$<XJU>,
    on_disconnect: $option.Option$<XJU>
  );
  /** @deprecated */
  open_shadow_root: boolean;
  /** @deprecated */
  adopt_styles: boolean;
  /** @deprecated */
  attributes: $dict.Dict$<string, (x0: string) => _.Result<XJU, undefined>>;
  /** @deprecated */
  properties: $dict.Dict$<string, $decode.Decoder$<XJU>>;
  /** @deprecated */
  contexts: $dict.Dict$<string, $decode.Decoder$<XJU>>;
  /** @deprecated */
  on_connect: $option.Option$<XJU>;
  /** @deprecated */
  on_disconnect: $option.Option$<XJU>;
}
export function Config$Config<XJU>(
  open_shadow_root: boolean,
  adopt_styles: boolean,
  attributes: $dict.Dict$<string, (x0: string) => _.Result<XJU, undefined>>,
  properties: $dict.Dict$<string, $decode.Decoder$<XJU>>,
  contexts: $dict.Dict$<string, $decode.Decoder$<XJU>>,
  on_connect: $option.Option$<XJU>,
  on_disconnect: $option.Option$<XJU>,
): Config$<XJU>;
export function Config$isConfig<XJU>(value: any): value is Config$<unknown>;
export function Config$Config$0<XJU>(value: Config$<XJU>): boolean;
export function Config$Config$open_shadow_root<XJU>(value: Config$<XJU>): boolean;
export function Config$Config$1<XJU>(
  value: Config$<XJU>,
): boolean;
export function Config$Config$adopt_styles<XJU>(value: Config$<XJU>): boolean;
export function Config$Config$2<XJU>(value: Config$<XJU>): $dict.Dict$<
  string,
  (x0: string) => _.Result<XJU, undefined>
>;
export function Config$Config$attributes<XJU>(value: Config$<XJU>): $dict.Dict$<
  string,
  (x0: string) => _.Result<XJU, undefined>
>;
export function Config$Config$3<XJU>(value: Config$<XJU>): $dict.Dict$<
  string,
  $decode.Decoder$<XJU>
>;
export function Config$Config$properties<XJU>(value: Config$<XJU>): $dict.Dict$<
  string,
  $decode.Decoder$<XJU>
>;
export function Config$Config$4<XJU>(value: Config$<XJU>): $dict.Dict$<
  string,
  $decode.Decoder$<XJU>
>;
export function Config$Config$contexts<XJU>(value: Config$<XJU>): $dict.Dict$<
  string,
  $decode.Decoder$<XJU>
>;
export function Config$Config$5<XJU>(value: Config$<XJU>): $option.Option$<XJU>;
export function Config$Config$on_connect<XJU>(value: Config$<XJU>): $option.Option$<
  XJU
>;
export function Config$Config$6<XJU>(value: Config$<XJU>): $option.Option$<XJU>;
export function Config$Config$on_disconnect<XJU>(value: Config$<XJU>): $option.Option$<
  XJU
>;

export type Config$<XJU> = Config<XJU>;

export class ClientDispatchedMessage extends _.CustomType {
  /** @deprecated */
  constructor(message: $transport.ServerMessage$);
  /** @deprecated */
  message: $transport.ServerMessage$;
}
export function Message$ClientDispatchedMessage<XJV>(
  message: $transport.ServerMessage$,
): Message$<XJV>;
export function Message$isClientDispatchedMessage<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$ClientDispatchedMessage$0<XJV>(value: Message$<XJV>): $transport.ServerMessage$;
export function Message$ClientDispatchedMessage$message<XJV>(
  value: Message$<XJV>,
): $transport.ServerMessage$;

export class ClientRegisteredSubject<XJV> extends _.CustomType {
  /** @deprecated */
  constructor(client: $process.Subject$<$transport.ClientMessage$<XJV>>);
  /** @deprecated */
  client: $process.Subject$<$transport.ClientMessage$<XJV>>;
}
export function Message$ClientRegisteredSubject<XJV>(
  client: $process.Subject$<$transport.ClientMessage$<XJV>>,
): Message$<XJV>;
export function Message$isClientRegisteredSubject<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$ClientRegisteredSubject$0<XJV>(value: Message$<XJV>): $process.Subject$<
  $transport.ClientMessage$<XJV>
>;
export function Message$ClientRegisteredSubject$client<XJV>(value: Message$<XJV>): $process.Subject$<
  $transport.ClientMessage$<XJV>
>;

export class ClientDeregisteredSubject<XJV> extends _.CustomType {
  /** @deprecated */
  constructor(client: $process.Subject$<$transport.ClientMessage$<XJV>>);
  /** @deprecated */
  client: $process.Subject$<$transport.ClientMessage$<XJV>>;
}
export function Message$ClientDeregisteredSubject<XJV>(
  client: $process.Subject$<$transport.ClientMessage$<XJV>>,
): Message$<XJV>;
export function Message$isClientDeregisteredSubject<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$ClientDeregisteredSubject$0<XJV>(value: Message$<XJV>): $process.Subject$<
  $transport.ClientMessage$<XJV>
>;
export function Message$ClientDeregisteredSubject$client<XJV>(value: Message$<
    XJV
  >): $process.Subject$<$transport.ClientMessage$<XJV>>;

export class ClientRegisteredCallback<XJV> extends _.CustomType {
  /** @deprecated */
  constructor(callback: (x0: $transport.ClientMessage$<XJV>) => undefined);
  /** @deprecated */
  callback: (x0: $transport.ClientMessage$<XJV>) => undefined;
}
export function Message$ClientRegisteredCallback<XJV>(
  callback: (x0: $transport.ClientMessage$<XJV>) => undefined,
): Message$<XJV>;
export function Message$isClientRegisteredCallback<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$ClientRegisteredCallback$0<XJV>(value: Message$<XJV>): (
  x0: $transport.ClientMessage$<XJV>
) => undefined;
export function Message$ClientRegisteredCallback$callback<XJV>(value: Message$<
    XJV
  >): (x0: $transport.ClientMessage$<XJV>) => undefined;

export class ClientDeregisteredCallback<XJV> extends _.CustomType {
  /** @deprecated */
  constructor(callback: (x0: $transport.ClientMessage$<XJV>) => undefined);
  /** @deprecated */
  callback: (x0: $transport.ClientMessage$<XJV>) => undefined;
}
export function Message$ClientDeregisteredCallback<XJV>(
  callback: (x0: $transport.ClientMessage$<XJV>) => undefined,
): Message$<XJV>;
export function Message$isClientDeregisteredCallback<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$ClientDeregisteredCallback$0<XJV>(value: Message$<XJV>): (
  x0: $transport.ClientMessage$<XJV>
) => undefined;
export function Message$ClientDeregisteredCallback$callback<XJV>(value: Message$<
    XJV
  >): (x0: $transport.ClientMessage$<XJV>) => undefined;

export class EffectAddedSelector<XJV> extends _.CustomType {
  /** @deprecated */
  constructor(selector: $process.Selector$<Message$<XJV>>);
  /** @deprecated */
  selector: $process.Selector$<Message$<XJV>>;
}
export function Message$EffectAddedSelector<XJV>(
  selector: $process.Selector$<Message$<XJV>>,
): Message$<XJV>;
export function Message$isEffectAddedSelector<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$EffectAddedSelector$0<XJV>(value: Message$<XJV>): $process.Selector$<
  Message$<XJV>
>;
export function Message$EffectAddedSelector$selector<XJV>(value: Message$<XJV>): $process.Selector$<
  Message$<XJV>
>;

export class EffectDispatchedMessage<XJV> extends _.CustomType {
  /** @deprecated */
  constructor(message: XJV);
  /** @deprecated */
  message: XJV;
}
export function Message$EffectDispatchedMessage<XJV>(
  message: XJV,
): Message$<XJV>;
export function Message$isEffectDispatchedMessage<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$EffectDispatchedMessage$0<XJV>(value: Message$<XJV>): XJV;
export function Message$EffectDispatchedMessage$message<XJV>(
  value: Message$<XJV>,
): XJV;

export class EffectEmitEvent extends _.CustomType {
  /** @deprecated */
  constructor(name: string, data: $json.Json$);
  /** @deprecated */
  name: string;
  /** @deprecated */
  data: $json.Json$;
}
export function Message$EffectEmitEvent<XJV>(
  name: string,
  data: $json.Json$,
): Message$<XJV>;
export function Message$isEffectEmitEvent<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$EffectEmitEvent$0<XJV>(value: Message$<XJV>): string;
export function Message$EffectEmitEvent$name<XJV>(value: Message$<XJV>): string;
export function Message$EffectEmitEvent$1<XJV>(value: Message$<XJV>): $json.Json$;
export function Message$EffectEmitEvent$data<XJV>(
  value: Message$<XJV>,
): $json.Json$;

export class EffectProvidedValue extends _.CustomType {
  /** @deprecated */
  constructor(key: string, value: $json.Json$);
  /** @deprecated */
  key: string;
  /** @deprecated */
  value: $json.Json$;
}
export function Message$EffectProvidedValue<XJV>(
  key: string,
  value: $json.Json$,
): Message$<XJV>;
export function Message$isEffectProvidedValue<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$EffectProvidedValue$0<XJV>(value: Message$<XJV>): string;
export function Message$EffectProvidedValue$key<XJV>(
  value: Message$<XJV>,
): string;
export function Message$EffectProvidedValue$1<XJV>(value: Message$<XJV>): $json.Json$;
export function Message$EffectProvidedValue$value<XJV>(
  value: Message$<XJV>,
): $json.Json$;

export class EffectRequestedContextSubscription<XJV> extends _.CustomType {
  /** @deprecated */
  constructor(key: string, decoder: $decode.Decoder$<XJV>);
  /** @deprecated */
  key: string;
  /** @deprecated */
  decoder: $decode.Decoder$<XJV>;
}
export function Message$EffectRequestedContextSubscription<XJV>(
  key: string,
  decoder: $decode.Decoder$<XJV>,
): Message$<XJV>;
export function Message$isEffectRequestedContextSubscription<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$EffectRequestedContextSubscription$0<XJV>(value: Message$<
    XJV
  >): string;
export function Message$EffectRequestedContextSubscription$key<XJV>(value: Message$<
    XJV
  >): string;
export function Message$EffectRequestedContextSubscription$1<XJV>(value: Message$<
    XJV
  >): $decode.Decoder$<XJV>;
export function Message$EffectRequestedContextSubscription$decoder<XJV>(value: Message$<
    XJV
  >): $decode.Decoder$<XJV>;

export class EffectRemovedContextSubscription extends _.CustomType {
  /** @deprecated */
  constructor(key: string);
  /** @deprecated */
  key: string;
}
export function Message$EffectRemovedContextSubscription<XJV>(
  key: string,
): Message$<XJV>;
export function Message$isEffectRemovedContextSubscription<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$EffectRemovedContextSubscription$0<XJV>(value: Message$<
    XJV
  >): string;
export function Message$EffectRemovedContextSubscription$key<XJV>(value: Message$<
    XJV
  >): string;

export class MonitorReportedDown extends _.CustomType {
  /** @deprecated */
  constructor(monitor: $process.Monitor$);
  /** @deprecated */
  monitor: $process.Monitor$;
}
export function Message$MonitorReportedDown<XJV>(
  monitor: $process.Monitor$,
): Message$<XJV>;
export function Message$isMonitorReportedDown<XJV>(
  value: any,
): value is Message$<unknown>;
export function Message$MonitorReportedDown$0<XJV>(value: Message$<XJV>): $process.Monitor$;
export function Message$MonitorReportedDown$monitor<XJV>(
  value: Message$<XJV>,
): $process.Monitor$;

export class SystemRequestedShutdown extends _.CustomType {}
export function Message$SystemRequestedShutdown<XJV>(): Message$<XJV>;
export function Message$isSystemRequestedShutdown<XJV>(
  value: any,
): value is Message$<unknown>;

export type Message$<XJV> = ClientDispatchedMessage | ClientRegisteredSubject<
  XJV
> | ClientDeregisteredSubject<XJV> | ClientRegisteredCallback<XJV> | ClientDeregisteredCallback<
  XJV
> | EffectAddedSelector<XJV> | EffectDispatchedMessage<XJV> | EffectEmitEvent | EffectProvidedValue | EffectRequestedContextSubscription<
  XJV
> | EffectRemovedContextSubscription | MonitorReportedDown | SystemRequestedShutdown;

export type ServerComponent = $process.Subject$<Message$<any>>;

export function start(x0: any, x1: any, x2: any, x3: any, x4: any, x5: any): _.Result<
  $actor.Started$<$process.Subject$<Message$<any>>>,
  $actor.StartError$
>;
