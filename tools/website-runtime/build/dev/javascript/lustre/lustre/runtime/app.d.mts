import type * as $process from "../../../gleam_erlang/gleam/erlang/process.d.mts";
import type * as $decode from "../../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as $option from "../../../gleam_stdlib/gleam/option.d.mts";
import type * as _ from "../../gleam.d.mts";
import type * as $effect from "../../lustre/effect.d.mts";
import type * as $runtime from "../../lustre/runtime/server/runtime.d.mts";
import type * as $vnode from "../../lustre/vdom/vnode.d.mts";

export class App<XMC, XMD, XME> extends _.CustomType {
  /** @deprecated */
  constructor(
    name: $option.Option$<$process.Name$<$runtime.Message$<XME>>>,
    init: (x0: XMC) => [XMD, $effect.Effect$<XME>],
    update: (x0: XMD, x1: XME) => [XMD, $effect.Effect$<XME>],
    view: (x0: XMD) => $vnode.Element$<XME>,
    config: Config$<XME>
  );
  /** @deprecated */
  name: $option.Option$<$process.Name$<$runtime.Message$<XME>>>;
  /** @deprecated */
  init: (x0: XMC) => [XMD, $effect.Effect$<XME>];
  /** @deprecated */
  update: (x0: XMD, x1: XME) => [XMD, $effect.Effect$<XME>];
  /** @deprecated */
  view: (x0: XMD) => $vnode.Element$<XME>;
  /** @deprecated */
  config: Config$<XME>;
}
export function App$App<XMC, XMD, XME>(
  name: $option.Option$<$process.Name$<$runtime.Message$<XME>>>,
  init: (x0: XMC) => [XMD, $effect.Effect$<XME>],
  update: (x0: XMD, x1: XME) => [XMD, $effect.Effect$<XME>],
  view: (x0: XMD) => $vnode.Element$<XME>,
  config: Config$<XME>,
): App$<XMC, XMD, XME>;
export function App$isApp<XMC, XMD, XME>(
  value: any,
): value is App$<unknown, unknown, unknown>;
export function App$App$0<XMC, XMD, XME>(value: App$<XMC, XMD, XME>): $option.Option$<
  $process.Name$<$runtime.Message$<XME>>
>;
export function App$App$name<XMC, XMD, XME>(value: App$<XMC, XMD, XME>): $option.Option$<
  $process.Name$<$runtime.Message$<XME>>
>;
export function App$App$1<XMC, XMD, XME>(value: App$<XMC, XMD, XME>): (x0: XMC) => [
  XMD,
  $effect.Effect$<XME>
];
export function App$App$init<XMC, XMD, XME>(value: App$<XMC, XMD, XME>): (
  x0: XMC
) => [XMD, $effect.Effect$<XME>];
export function App$App$2<XMC, XMD, XME>(value: App$<XMC, XMD, XME>): (
  x0: XMD,
  x1: XME
) => [XMD, $effect.Effect$<XME>];
export function App$App$update<XMC, XMD, XME>(value: App$<XMC, XMD, XME>): (
  x0: XMD,
  x1: XME
) => [XMD, $effect.Effect$<XME>];
export function App$App$3<XMC, XMD, XME>(value: App$<XMC, XMD, XME>): (x0: XMD) => $vnode.Element$<
  XME
>;
export function App$App$view<XMC, XMD, XME>(value: App$<XMC, XMD, XME>): (
  x0: XMD
) => $vnode.Element$<XME>;
export function App$App$4<XMC, XMD, XME>(value: App$<XMC, XMD, XME>): Config$<
  XME
>;
export function App$App$config<XMC, XMD, XME>(value: App$<XMC, XMD, XME>): Config$<
  XME
>;

export type App$<XMC, XMD, XME> = App<XMC, XMD, XME>;

export class Config<XMF> extends _.CustomType {
  /** @deprecated */
  constructor(
    open_shadow_root: boolean,
    adopt_styles: boolean,
    delegates_focus: boolean,
    attributes: _.List<[string, (x0: string) => _.Result<XMF, undefined>]>,
    properties: _.List<[string, $decode.Decoder$<XMF>]>,
    contexts: _.List<[string, $decode.Decoder$<XMF>]>,
    is_form_associated: boolean,
    on_form_autofill: $option.Option$<(x0: string) => XMF>,
    on_form_reset: $option.Option$<XMF>,
    on_form_restore: $option.Option$<(x0: string) => XMF>,
    on_form_disabled: $option.Option$<(x0: boolean) => XMF>,
    on_connect: $option.Option$<XMF>,
    on_adopt: $option.Option$<XMF>,
    on_disconnect: $option.Option$<XMF>
  );
  /** @deprecated */
  open_shadow_root: boolean;
  /** @deprecated */
  adopt_styles: boolean;
  /** @deprecated */
  delegates_focus: boolean;
  /** @deprecated */
  attributes: _.List<[string, (x0: string) => _.Result<XMF, undefined>]>;
  /** @deprecated */
  properties: _.List<[string, $decode.Decoder$<XMF>]>;
  /** @deprecated */
  contexts: _.List<[string, $decode.Decoder$<XMF>]>;
  /** @deprecated */
  is_form_associated: boolean;
  /** @deprecated */
  on_form_autofill: $option.Option$<(x0: string) => XMF>;
  /** @deprecated */
  on_form_reset: $option.Option$<XMF>;
  /** @deprecated */
  on_form_restore: $option.Option$<(x0: string) => XMF>;
  /** @deprecated */
  on_form_disabled: $option.Option$<(x0: boolean) => XMF>;
  /** @deprecated */
  on_connect: $option.Option$<XMF>;
  /** @deprecated */
  on_adopt: $option.Option$<XMF>;
  /** @deprecated */
  on_disconnect: $option.Option$<XMF>;
}
export function Config$Config<XMF>(
  open_shadow_root: boolean,
  adopt_styles: boolean,
  delegates_focus: boolean,
  attributes: _.List<[string, (x0: string) => _.Result<XMF, undefined>]>,
  properties: _.List<[string, $decode.Decoder$<XMF>]>,
  contexts: _.List<[string, $decode.Decoder$<XMF>]>,
  is_form_associated: boolean,
  on_form_autofill: $option.Option$<(x0: string) => XMF>,
  on_form_reset: $option.Option$<XMF>,
  on_form_restore: $option.Option$<(x0: string) => XMF>,
  on_form_disabled: $option.Option$<(x0: boolean) => XMF>,
  on_connect: $option.Option$<XMF>,
  on_adopt: $option.Option$<XMF>,
  on_disconnect: $option.Option$<XMF>,
): Config$<XMF>;
export function Config$isConfig<XMF>(value: any): value is Config$<unknown>;
export function Config$Config$0<XMF>(value: Config$<XMF>): boolean;
export function Config$Config$open_shadow_root<XMF>(value: Config$<XMF>): boolean;
export function Config$Config$1<XMF>(
  value: Config$<XMF>,
): boolean;
export function Config$Config$adopt_styles<XMF>(value: Config$<XMF>): boolean;
export function Config$Config$2<XMF>(value: Config$<XMF>): boolean;
export function Config$Config$delegates_focus<XMF>(value: Config$<XMF>): boolean;
export function Config$Config$3<XMF>(
  value: Config$<XMF>,
): _.List<[string, (x0: string) => _.Result<XMF, undefined>]>;
export function Config$Config$attributes<XMF>(value: Config$<XMF>): _.List<
  [string, (x0: string) => _.Result<XMF, undefined>]
>;
export function Config$Config$4<XMF>(value: Config$<XMF>): _.List<
  [string, $decode.Decoder$<XMF>]
>;
export function Config$Config$properties<XMF>(value: Config$<XMF>): _.List<
  [string, $decode.Decoder$<XMF>]
>;
export function Config$Config$5<XMF>(value: Config$<XMF>): _.List<
  [string, $decode.Decoder$<XMF>]
>;
export function Config$Config$contexts<XMF>(value: Config$<XMF>): _.List<
  [string, $decode.Decoder$<XMF>]
>;
export function Config$Config$6<XMF>(value: Config$<XMF>): boolean;
export function Config$Config$is_form_associated<XMF>(value: Config$<XMF>): boolean;
export function Config$Config$7<XMF>(
  value: Config$<XMF>,
): $option.Option$<(x0: string) => XMF>;
export function Config$Config$on_form_autofill<XMF>(value: Config$<XMF>): $option.Option$<
  (x0: string) => XMF
>;
export function Config$Config$8<XMF>(value: Config$<XMF>): $option.Option$<XMF>;
export function Config$Config$on_form_reset<XMF>(value: Config$<XMF>): $option.Option$<
  XMF
>;
export function Config$Config$9<XMF>(value: Config$<XMF>): $option.Option$<
  (x0: string) => XMF
>;
export function Config$Config$on_form_restore<XMF>(value: Config$<XMF>): $option.Option$<
  (x0: string) => XMF
>;
export function Config$Config$10<XMF>(value: Config$<XMF>): $option.Option$<
  (x0: boolean) => XMF
>;
export function Config$Config$on_form_disabled<XMF>(value: Config$<XMF>): $option.Option$<
  (x0: boolean) => XMF
>;
export function Config$Config$11<XMF>(value: Config$<XMF>): $option.Option$<XMF>;
export function Config$Config$on_connect<XMF>(
  value: Config$<XMF>,
): $option.Option$<XMF>;
export function Config$Config$12<XMF>(value: Config$<XMF>): $option.Option$<XMF>;
export function Config$Config$on_adopt<XMF>(
  value: Config$<XMF>,
): $option.Option$<XMF>;
export function Config$Config$13<XMF>(value: Config$<XMF>): $option.Option$<XMF>;
export function Config$Config$on_disconnect<XMF>(
  value: Config$<XMF>,
): $option.Option$<XMF>;

export type Config$<XMF> = Config<XMF>;

export class Option<XMG> extends _.CustomType {
  /** @deprecated */
  constructor(apply: (x0: Config$<XMG>) => Config$<XMG>);
  /** @deprecated */
  apply: (x0: Config$<XMG>) => Config$<XMG>;
}
export function Option$Option<XMG>(
  apply: (x0: Config$<XMG>) => Config$<XMG>,
): Option$<XMG>;
export function Option$isOption<XMG>(value: any): value is Option$<unknown>;
export function Option$Option$0<XMG>(value: Option$<XMG>): (x0: Config$<XMG>) => Config$<
  XMG
>;
export function Option$Option$apply<XMG>(value: Option$<XMG>): (
  x0: Config$<XMG>
) => Config$<XMG>;

export type Option$<XMG> = Option<XMG>;

export const default_config: Config$<any>;

export function configure<XMH>(options: _.List<Option$<XMH>>): Config$<XMH>;

export function configure_server_component<XML>(config: Config$<XML>): $runtime.Config$<
  XML
>;
