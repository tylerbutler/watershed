import type * as $dynamic from "../../gleam_stdlib/gleam/dynamic.d.mts";
import type * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.d.mts";
import type * as _ from "../gleam.d.mts";
import type * as $effect from "../lustre/effect.d.mts";
import type * as $app from "../lustre/runtime/app.d.mts";
import type * as $vattr from "../lustre/vdom/vattr.d.mts";
import type * as $vnode from "../lustre/vdom/vnode.d.mts";

export type Config = $app.Config$<any>;

export type Option = $app.Option$<any>;

export function on_attribute_change<XPA>(
  name: string,
  decoder: (x0: string) => _.Result<XPA, undefined>
): $app.Option$<XPA>;

export function on_property_change<XPE>(
  name: string,
  decoder: $decode.Decoder$<XPE>
): $app.Option$<XPE>;

export function on_context_change<XPH>(
  key: string,
  decoder: $decode.Decoder$<XPH>
): $app.Option$<XPH>;

export function form_associated(): $app.Option$<any>;

export function on_form_autofill<XPM>(handler: (x0: string) => XPM): $app.Option$<
  XPM
>;

export function on_form_reset<XPO>(message: XPO): $app.Option$<XPO>;

export function on_form_restore<XPQ>(handler: (x0: string) => XPQ): $app.Option$<
  XPQ
>;

export function on_form_disabled<XPS>(handler: (x0: boolean) => XPS): $app.Option$<
  XPS
>;

export function open_shadow_root(open: boolean): $app.Option$<any>;

export function adopt_styles(adopt: boolean): $app.Option$<any>;

export function delegates_focus(delegates: boolean): $app.Option$<any>;

export function on_connect<XQA>(message: XQA): $app.Option$<XQA>;

export function on_adopt<XQC>(message: XQC): $app.Option$<XQC>;

export function on_disconnect<XQE>(message: XQE): $app.Option$<XQE>;

export function default_slot<XQG>(
  attributes: _.List<$vattr.Attribute$<XQG>>,
  fallback: _.List<$vnode.Element$<XQG>>
): $vnode.Element$<XQG>;

export function named_slot<XQM>(
  name: string,
  attributes: _.List<$vattr.Attribute$<XQM>>,
  fallback: _.List<$vnode.Element$<XQM>>
): $vnode.Element$<XQM>;

export function part(name: string): $vattr.Attribute$<any>;

export function parts(names: _.List<[string, boolean]>): $vattr.Attribute$<any>;

export function exportparts(names: _.List<string>): $vattr.Attribute$<any>;

export function slot(name: string): $vattr.Attribute$<any>;

export function set_form_value(value: string): $effect.Effect$<any>;

export function clear_form_value(): $effect.Effect$<any>;

export function set_pseudo_state(value: string): $effect.Effect$<any>;

export function remove_pseudo_state(value: string): $effect.Effect$<any>;

export function prerender<XRM>(
  component: $app.App$<undefined, any, XRM>,
  tag: string,
  attributes: _.List<$vattr.Attribute$<XRM>>,
  children: _.List<$vnode.Element$<XRM>>
): $vnode.Element$<XRM>;
